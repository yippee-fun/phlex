# frozen_string_literal: true

module Phlex::Compiler
	class Formatter < VerbatimFormatter
		def initialize
			super
			@new_line_character = "\n"
			@indentation_character = "\t"
			@level = 0
		end

		def visit(node)
			case node
			when nil
				nil
			when Array
				visit_array(node)
			when Proc
				node.call(self)
			else
				super
			end
		end

		def visit_array(nodes)
			nodes.each do |node|
				case node
				when Array
					indent { visit_array(node) }
				else
					visit(node)
				end
			end
		end

		def format(node)
			@buffer.clear
			visit(node)
			@buffer.join
		end

		def visit_each(nodes)
			i, len = 0, nodes.length
			if block_given?
				while i < len
					node = nodes[i]
					i += 1
					if node
						visit node
						yield unless i == len
					end
				end
			else
				while i < len
					visit nodes[i]
					i += 1
				end
			end
		end

		def space
			push " "
		end

		def statement
			ensure_new_line
			yield
		end

		def ensure_new_line
			new_line unless on_new_line?
		end

		def on_new_line?
			@new_line_at == @buffer.length
		end

		def new_line
			push "#{@new_line_character}#{@indentation_character * @level}"
			@new_line_at = @buffer.length
		end

		def indent
			original_level = @level
			@level += 1
			ensure_new_line
			yield
			@level = original_level
		end

		def visit_block_node(node)
			emit node.opening_loc
			indent do
				visit node.body
			end
			new_line
			emit node.closing_loc
		end

		def visit_call_node(node)
			visit node.receiver
			emit node.call_operator_loc
			emit node.message_loc
			emit node.opening_loc
			visit node.arguments
			emit node.closing_loc
			space
			visit node.block
		end

		def visit_def_node(node)
			emit node.def_keyword_loc
			space
			push node.name

			if node.parameters
				push "("
				visit node.parameters
				push ")"
			end

			indent { visit node.body }

			new_line
			emit node.end_keyword_loc
		end

		def visit_statements_node(node)
			visit_each(node.compact_child_nodes) { ensure_new_line }
		end
	end
end
