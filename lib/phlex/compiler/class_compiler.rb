# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Refract::Visitor
	def initialize(component, path)
		super()
		@component = component
		@path = path
		@compiled_snippets = []
	end

	def compile(node)
		visit(node.body)
		@compiled_snippets.compact.freeze
	end

	visit Refract::DefNode do |node|
		return if node.name == :initialize
		return if node.receiver

		method = begin
			Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name)
		rescue NameError
			nil
		end

		return unless method
		path, lineno = method.source_location
		return unless @path == path
		return unless node.start_line == lineno

		@compiled_snippets << Phlex::Compiler::MethodCompiler.new(
			@component
		).compile(node)
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
end
