# frozen_string_literal: true

module Phlex::Compiler
	class Formatter < VerbatimFormatter
		def visit(node)
			case node
			when nil
				nil
			when String
				push node
			when Array, Set
				node.each { |n| visit(n) }
			when Proc
				visit node.call
			when :new_line
				new_line
			when :space
				space
			else
				super
			end
		end

		def format(node)
			@buffer.clear
			visit(node)
			[@buffer.join, @source_map]
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

		def statement
			new_line
			yield
		end

		def parens
			push "("
			yield
			push ")"
		end

		def new_line
			push "\n"
		end

		def space
			push " "
		end

		def visit_block_node(node)
			emit node.opening_loc
			new_line
			visit node.body
			new_line
			emit node.closing_loc
		end

		def visit_call_node(node)
			visit node.receiver
			emit node.call_operator_loc
			emit node.message_loc
			if node.opening_loc
				emit node.opening_loc
			else
				space
			end
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
				parens do
					visit node.parameters
				end
			end

			new_line
			visit node.body

			new_line
			emit node.end_keyword_loc
		end

		def visit_statements_node(node)
			visit_each(node.compact_child_nodes) { new_line }
		end
	end
end
