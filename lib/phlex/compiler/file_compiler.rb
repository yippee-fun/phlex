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

	def initialize(path, targets:, diagnostics: Phlex::Compiler::Diagnostics.new(path), recompile: false)
		super()
		@path = path
		@targets = targets
		@diagnostics = diagnostics
		@recompile = recompile
		@current_namespace = []
		@definitions = []
		@usings = []
	end

	def compile(node)
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

	# Ruby offers no way to read the `ruby2_keywords` flag back, so a compiled
	# method would lose it.
	visit Refract::CallNode do |node|
		if node.receiver.nil?
			case node.name
			in :using then @usings << Scoped.new(namespace: @current_namespace.dup.freeze, node:)
			in :ruby2_keywords then @diagnostics.refuse(node, "ruby2_keywords can't be preserved by the compiler")
			else nil
			end
		end

		super(node)
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

	# Two definitions of a method on one line share a source location, so
	# neither can be told apart from the live method.
	private def unique_definitions
		@definitions.group_by { |definition| [definition.node.name, definition.node.start_line] }.filter_map do |_key, definitions|
			next definitions.first if definitions.one?

			@diagnostics.refuse(definitions.first.node, "#{definitions.first.node.name} is defined more than once on this line, so the compiler can't tell which is live")
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
			else
				targeted << definition
			end
		end
	end

	private def compile_namespace(namespace, definitions)
		probe = Phlex::Compiler.probe(namespace)
		environments = {}.compare_by_identity

		definitions.group_by { |definition| @targets[definition.node.start_line].component }.map do |component, component_definitions|
			unless probe.component.equal?(component)
				first = component_definitions.first.node
				raise Phlex::Compiler::Error, "#{@path}:#{first.start_line} defines #{component}##{first.name}, but reopening its class and module statements reaches #{probe.component.inspect}"
			end

			environment = environments[component] ||= Phlex::Compiler::Environment.new(component, standard_set: probe.set.equal?(::Set))
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
		if component.private_instance_methods(false).include?(name)
			:private
		elsif component.protected_instance_methods(false).include?(name)
			:protected
		else
			:public
		end
	end
end
