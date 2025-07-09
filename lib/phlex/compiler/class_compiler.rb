# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Prism::Visitor
	def initialize(compiler)
		@compiler = compiler
	end

	def compile(node)
		visit_all(node.child_nodes)
	end

	def visit_def_node(node)
		return if node.name == :initialize
		return if node.receiver

		compiled_source = Phlex::Compiler::MethodCompiler.new(@compiler.component).compile(node)

		if compiled_source
			# puts compiled_source
			@compiler.redefine_method(compiled_source, node.location.start_line)
		end
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
