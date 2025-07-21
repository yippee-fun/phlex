# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Refract::Visitor
	def initialize(compiler)
		super()
		@compiler = compiler
		@compiled_snippets = []
	end

	def compile(node)
		visit(node.body)
		@compiled_snippets.freeze
	end

	visit Refract::DefNode do |node|
		return if node.name == :initialize
		return if node.receiver

		@compiled_snippets << Phlex::Compiler::MethodCompiler.new(
			@compiler.component
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
