# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Prism::Visitor
	def initialize(compiler)
		@compiler = compiler
	end

	def compile(node)
		visit_all(node.child_nodes)
	end

	def visit_def_node(node)
		Phlex::Compiler::MethodCompiler.new(@compiler).compile(node)
	end

	def visit_class_node(node)
		nil
	end

	def visit_module_node(node)
		nil
	end

	def visit_block_node(node)
		nil
	end
end
