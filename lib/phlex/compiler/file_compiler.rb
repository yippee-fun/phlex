# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Refract::Visitor
	Result = Data.define(:namespace, :compiled_snippets)

	def initialize(compiler)
		super()
		@compiler = compiler
		@current_namespace = []
	end

	def compile(node)
		catch(:phlex_compiler_result) do
			visit(node)
		end
	end

	visit Refract::ModuleNode do |node|
		@current_namespace.push(node)
		super(node)
		@current_namespace.pop
	end

	visit Refract::ClassNode do |node|
		@current_namespace.push(node)

		if @compiler.line == node.start_line
			throw :phlex_compiler_result, Result.new(
				namespace: @current_namespace.dup.freeze,
				compiled_snippets: Phlex::Compiler::ClassCompiler.new(@compiler).compile(node)
			)
		else
			super(node)
		end

		@current_namespace.pop
	end

	visit Refract::DefNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end
end
