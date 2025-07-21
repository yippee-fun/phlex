# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Refract::Visitor
	def initialize(compiler)
		super()
		@compiler = compiler
	end

	def compile(node)
		visit(node.body)
	end

	visit Refract::DefNode do |node|
		return if node.name == :initialize
		return if node.receiver

		compiled_source = Phlex::Compiler::MethodCompiler.new(@compiler.component).compile(node)

		if compiled_source
			@compiler.redefine_method(compiled_source, node.start_line)
		end
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
