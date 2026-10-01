# frozen_string_literal: true

# Finds the definitions in a file that are the live methods of the given
# components, and compiles them. Which class a `class` statement names is
# never worked out from its constant path: a definition is compiled only
# when a component's method has that file and line as its source location,
# and the enclosing class and module statements are then reopened with a
# probe so Ruby itself confirms they name that component.
class Phlex::Compiler::FileCompiler < Refract::Visitor
	Result = Data.define(:namespace, :component, :compiled_snippets, :visibilities, :inlined)

	# A statement in the file and the class and module statements around it.
	Scoped = Data.define(:namespace, :node)

	def initialize(path, targets:, diagnostics: Phlex::Compiler::Diagnostics.new(path), recompile: false, inline: true)
		super()
		@path = path
		@targets = targets
		@diagnostics = diagnostics
		@recompile = recompile
		@inline = inline
		@current_namespace = []
		@definitions = []
		@usings = []
		@keyword_flagged = []
		@compiled_lines = []
	end

	def compile(node)
		@top_level = node.statements
		visit(node)
		results = definitions_by_namespace.flat_map do |namespace, definitions|
			compile_namespace(namespace, definitions)
		end
		return [].freeze unless refinements_reproducible?

		results.freeze
	end

	# The `using` statements to put before the compiled definitions.
	def usings
		@usings.map(&:node)
	end

	visit Refract::ModuleNode do |node|
		@current_namespace.push(node)
		super(node)
		@current_namespace.pop
	end

	visit Refract::ClassNode do |node|
		@current_namespace.push(node)
		super(node)
		@current_namespace.pop
	end

	visit Refract::DefNode do |node|
		@definitions << Scoped.new(namespace: @current_namespace.dup.freeze, node:) unless node.receiver
	end

	visit Refract::BlockNode do |node|
		nil
	end

	# A `using` is copied into the compiled source, so it has to be a plain
	# top-level statement naming a constant: one inside a conditional or
	# using a local would mean something else there. Ruby offers no way to
	# read the `ruby2_keywords` flag back, so a method marked with it is
	# refused if it's compiled.
	visit Refract::CallNode do |node|
		if node.receiver.nil?
			case node.name
			in :using
				# A refused `using` isn't copied, since its constant or local may
				# not be reachable from the probe's fresh scope.
				if @stack[-2].equal?(@top_level) && node.arguments&.arguments in [Refract::ConstantReadNode | Refract::ConstantPathNode]
					@usings << Scoped.new(namespace: @current_namespace.dup.freeze, node:)
				else
					@diagnostics.refuse(node, "this `using` isn't a plain top-level statement naming a constant, which the compiler can't reproduce")
				end
			in :ruby2_keywords
				@keyword_flagged.concat(ruby2_keywords_names(node).map { |name| Scoped.new(namespace: @current_namespace.dup.freeze, node: name) })
			else nil
			end
		end

		super(node)
	end

	private def ruby2_keywords_names(node)
		(node.arguments&.arguments || []).map do |argument|
			case argument
			in Refract::SymbolNode then argument.unescaped.to_sym
			in Refract::DefNode then argument.name
			else @diagnostics.refuse(node, "ruby2_keywords is given arguments the compiler can't read, so it can't tell which methods it marks")
			end
		end
	end

	# A refinement applies from its `using` to the end of the scope, so it can
	# only be reproduced when every `using` comes before the definitions that
	# are replaced. Definitions above it that are left alone don't matter.
	private def refinements_reproducible?
		first_definition = @compiled_lines.min
		# A `using` on the same line as the first replaced definition may follow
		# it, so it's refused too.
		partial = @usings.find { |using| !using.namespace.empty? || (first_definition && using.node.start_line >= first_definition) }
		return true unless partial

		@diagnostics.refuse(partial.node, "this `using` applies to only part of the file, which the compiler can't reproduce")
		false
	end

	# A definition with no live method at its line is usually just one that a
	# later definition replaced: a live method not made by `def`, such as one
	# from `attr_reader` or `define_method`, is never a target. It means the
	# file has changed since it was loaded when a live method of the same name
	# has no definition at its own line, in which case compiling from this
	# file would install the wrong code. A compiled method was always made by
	# `def`, so its line having no definition of it means the same, and
	# recompiling would leave the compiled method in place.
	private def definitions_by_namespace
		orphaned = @targets.values.reject do |target|
			@definitions.any? { |definition| definition.node.start_line == target.line && definition.node.name == target.name }
		end

		orphaned.each do |target|
			next unless target.replaced

			@diagnostics.refuse(target.line, "#{target.name} was compiled from this line, which no longer defines it, so the file has changed since it was loaded")
		end

		unique_definitions.group_by(&:namespace).filter_map do |namespace, definitions|
			targeted, compiled, unmatched = partition_by_target(definitions)

			compiled.each { |definition| @diagnostics.report(definition.node, "#{definition.node.name} is already compiled") }

			unmatched.each do |definition|
				next unless orphaned.any? { |target| target.name == definition.node.name }

				@diagnostics.refuse(definition.node, "no live method is defined at this line, so the file has changed since it was loaded")
			end

			[namespace, targeted] unless targeted.empty?
		end.to_h
	end

	# Two definitions on one line share a source location, so a live method
	# there can't be matched to either, whatever their names or classes. Lines
	# with no live method on them aren't compiled, so they're left unmatched.
	private def unique_definitions
		@definitions.group_by { |definition| definition.node.start_line }.flat_map do |line, definitions|
			next definitions if definitions.one? || !@targets.key?(line)

			@diagnostics.refuse(definitions.first.node, "more than one method is defined on this line, so the compiler can't tell which definition is live")
			[]
		end
	end

	private def partition_by_target(definitions)
		definitions.each_with_object([[], [], []]) do |definition, (targeted, compiled, unmatched)|
			target = @targets[definition.node.start_line]

			if target.nil? || target.name != definition.node.name
				unmatched << definition
			elsif target.compiled
				compiled << definition
			elsif keyword_flagged?(target)
				# Matched by name alone, since the mark can sit in a later reopening
				# of the class, whose statements are different nodes.
				@diagnostics.refuse(definition.node, "#{definition.node.name} is marked ruby2_keywords in this file, which the compiler can't preserve")
			else
				targeted << definition
			end
		end
	end

	# Marking an alias marks the body it shares with the method, so the
	# method's aliases are checked too. A mark of the alias's name counts only
	# when it's made in the alias's own class.
	private def keyword_flagged?(target)
		return false if @keyword_flagged.empty?
		return true if @keyword_flagged.any? { |flagged| flagged.node == target.name }

		Phlex::Compiler.aliases_sharing(target.component, target.name).any? do |owner, name|
			@keyword_flagged.any? { |flagged| flagged.node == name && reaches?(flagged.namespace, owner) }
		end
	end

	private def reaches?(namespace, component)
		Phlex::Compiler.probe(namespace).component.equal?(component)
	rescue Phlex::Compiler::Error
		false
	end

	private def compile_namespace(namespace, definitions)
		probe = Phlex::Compiler.probe(namespace, usings:)
		environments = {}.compare_by_identity

		definitions.group_by { |definition| @targets[definition.node.start_line].component }.map do |component, component_definitions|
			unless probe.component.equal?(component)
				first = component_definitions.first.node
				raise Phlex::Compiler::Error, "#{@path}:#{first.start_line} defines #{component}##{first.name}, but reopening its class and module statements reaches #{probe.component.inspect}"
			end

			environment = environments[component] ||= Phlex::Compiler::Environment.new(component, standard_set: probe.set.equal?(::Set), method_resolver: probe.method_resolver, inline: @inline)
			snippets = []
			visibilities = {}

			component_definitions.each do |definition|
				# The original is reinstalled only over a compiled method. One that
				# was never replaced is already live, and copying it could put it
				# below a `using` it was above.
				keep_uncompiled = @recompile && @targets[definition.node.start_line].replaced
				compiled = Phlex::Compiler::MethodCompiler.new(environment, @path, diagnostics: @diagnostics).compile(definition.node, keep_uncompiled:)
				next unless compiled

				snippets << compiled
				@compiled_lines << definition.node.start_line
				visibilities[definition.node.name] = visibility_of(component, definition.node.name)
			end

			Result.new(namespace:, component:, compiled_snippets: snippets.freeze, visibilities: visibilities.freeze, inlined: environment.inlined)
		end
	end

	private def visibility_of(component, name)
		if component.private_instance_methods(false).include?(name)
			:private
		elsif component.protected_instance_methods(false).include?(name)
			:protected
		else
			:public
		end
	end
end
