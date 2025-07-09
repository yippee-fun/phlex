# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Prism::Visitor
	def initialize(compiler)
		@compiler = compiler
	end

	def compile(node)
		visit(node)
	end

	def visit_class_node(node)
		if @compiler.line == node.location.start_line
			Phlex::Compiler::ClassCompiler.new(@compiler).compile(node)
		end
	end

	# def visit_module_node(node)
	# 	super
	# end

	def visit_def_node(node)
		nil
	end

	def visit_block_node(node)
		nil
	end
end
