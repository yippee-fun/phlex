# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Refract::Visitor
	attr_reader :visibilities

	def initialize(component, path, nesting: [component])
		super()
		@component = component
		@path = path
		@nesting = nesting
		@definitions = []
		@compiled_snippets = []
		@visibilities = {}
	end

	def compile(node)
		visit(node.body)

		# Two definitions of a method on one line share a source location, so
		# neither can be told apart from the live method.
		@definitions.group_by { |definition| [definition.name, definition.start_line] }.each_value do |definitions|
			compile_definition(definitions.first) if definitions.one?
		end

		@compiled_snippets.freeze
	end

	visit Refract::DefNode do |node|
		return if node.name == :initialize
		return if node.receiver

		@definitions << node
	end

	visit Refract::ClassNode do |node|
		nil
	end

	visit Refract::ModuleNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end

	private def compile_definition(node)
		method = begin
			Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name)
		rescue NameError
			nil
		end

		return unless method
		path, lineno = method.source_location
		return unless @path == path
		return unless node.start_line == lineno

		compiled = Phlex::Compiler::MethodCompiler.new(@component, @path, nesting: @nesting).compile(node)
		return unless compiled

		@compiled_snippets << compiled
		@visibilities[node.name] = visibility_of(node.name)
	end

	private def visibility_of(name)
		if @component.private_instance_methods(false).include?(name)
			:private
		elsif @component.protected_instance_methods(false).include?(name)
			:protected
		else
			:public
		end
	end
end
