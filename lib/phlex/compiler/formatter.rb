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
			# Check if this is a unary operator
			# Unary operators are either:
			# 1. Named with @ suffix (like -@, +@)
			# 2. ! or ~ with no arguments
			is_unary = case node.name
			when :-@, :+@
				true
			when :!, :~
				node.arguments.nil?
			else
				false
			end
			
			if is_unary && node.receiver && !node.call_operator_loc
				# For unary operators, emit the operator first
				emit node.message_loc
				visit node.receiver
			else
				# Regular method call (including binary operators)
				visit node.receiver
				emit node.call_operator_loc
				
				# For [] calls, message_loc includes the brackets and arguments,
				# so we should not emit it to avoid duplication
				if node.name != :[]
					emit node.message_loc
				end
			end
			
			if node.opening_loc
				emit node.opening_loc
			elsif node.arguments || node.block
				space
			end
			
			visit node.arguments
			
			# Handle block arguments that should be inside parentheses
			if node.block.is_a?(Prism::BlockArgumentNode)
				# Add comma if there were arguments
				push ", " if node.arguments
				visit node.block
			end
			
			emit node.closing_loc
			
			# Handle regular blocks (outside parentheses)
			if node.block && !node.block.is_a?(Prism::BlockArgumentNode)
				space
				visit node.block
			end
		end

		def visit_def_node(node)
			push "def"
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
			push "end"
		end

		def visit_statements_node(node)
			visit_each(node.compact_child_nodes) { new_line }
		end

		def visit_interpolated_string_node(node)
			push '"'
			node.parts.each do |part|
				case part
				when Prism::StringNode
					push part.unescaped.gsub('"', '\"')
				when Prism::EmbeddedStatementsNode
					visit(part)
				end
			end
			push '"'
		end
	end
end
