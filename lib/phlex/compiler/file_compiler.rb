# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Refract::Visitor
	def initialize(compiler)
		super()
		@compiler = compiler
	end

	def compile(node)
		visit(node)
	end

	visit Refract::ClassNode do |node|
		if @compiler.line == node.start_line
			Phlex::Compiler::ClassCompiler.new(@compiler).compile(node)
		end
	end

	# def visit_module_node(node)
	# 	super
	# end

	visit Refract::DefNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end
end
