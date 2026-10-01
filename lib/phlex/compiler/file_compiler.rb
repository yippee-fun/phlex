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
	end

	def compile(node)
		@top_level = node.statements
		visit(node)
		return [].freeze unless refinements_reproducible?

		definitions_by_namespace.flat_map do |namespace, definitions|
			compile_namespace(namespace, definitions)
		end.freeze
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
				unless @stack[-2].equal?(@top_level) && node.arguments&.arguments in [Refract::ConstantReadNode | Refract::ConstantPathNode]
					@diagnostics.refuse(node, "this `using` isn't a plain top-level statement naming a constant, which the compiler can't reproduce")
				end

				@usings << Scoped.new(namespace: @current_namespace.dup.freeze, node:)
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
	# only be reproduced for the whole file when every `using` is at the top.
	private def refinements_reproducible?
		first_definition = @definitions.map { |definition| definition.node.start_line }.min
		partial = @usings.find { |using| !using.namespace.empty? || (first_definition && using.node.start_line > first_definition) }
		return true unless partial

		@diagnostics.refuse(partial.node, "this `using` applies to only part of the file, which the compiler can't reproduce")
		false
	end

	# A definition with no live method at its line is usually just one that a
	# later definition replaced. It means the file has changed since it was
	# loaded when a live method of the same name has no definition at its own
	# line, in which case compiling from this file would install the wrong code.
	private def definitions_by_namespace
		orphaned = @targets.values.reject do |target|
			@definitions.any? { |definition| definition.node.start_line == target.line && definition.node.name == target.name }
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
	# there can't be matched to either, whatever their names or classes.
	private def unique_definitions
		@definitions.group_by { |definition| definition.node.start_line }.filter_map do |_line, definitions|
			next definitions.first if definitions.one?

			@diagnostics.refuse(definitions.first.node, "more than one method is defined on this line, so the compiler can't tell which definition is live")
			nil
		end
	end

	private def partition_by_target(definitions)
		definitions.each_with_object([[], [], []]) do |definition, (targeted, compiled, unmatched)|
			target = @targets[definition.node.start_line]

			if target.nil? || target.name != definition.node.name
				unmatched << definition
			elsif target.compiled
				compiled << definition
			elsif @keyword_flagged.any? { |flagged| flagged.node == definition.node.name }
				# Matched by name alone, since the mark can sit in a later reopening
				# of the class, whose statements are different nodes.
				@diagnostics.refuse(definition.node, "#{definition.node.name} is marked ruby2_keywords in this file, which the compiler can't preserve")
			else
				targeted << definition
			end
		end
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
				compiled = Phlex::Compiler::MethodCompiler.new(environment, @path, diagnostics: @diagnostics).compile(definition.node, keep_uncompiled: @recompile)
				next unless compiled

				snippets << compiled
				visibilities[definition.node.name] = visibility_of(component, definition.node.name)
			end

			Result.new(namespace:, component:, compiled_snippets: snippets.freeze, visibilities: visibilities.freeze, inlined: environment.inlined)
		end
	end

	private def visibility_of(component, name)
		if component.private_method_defined?(name, false)
			:private
		elsif component.protected_method_defined?(name, false)
			:protected
		else
			:public
		end
	end
end
