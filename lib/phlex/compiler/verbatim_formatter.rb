# frozen_string_literal: true

module Phlex::Compiler
	class VerbatimFormatter < Prism::BasicVisitor
		def initialize
			@buffer = []
			@source_map = []
			@current_line = 1
		end

		def push(value)
			string = case value
			when String
				value
			when Symbol
				value.name
			end

			@buffer << string
			new_lines = string.count("\n")
			@current_line += new_lines
		end

		def emit(node)
			return unless node
			source_map = @source_map
			current_line = @current_line
			start_line = node.start_line
			end_line = node.end_line
			number_of_lines = end_line - start_line
			i = 0
			while i <= number_of_lines
				source_map[current_line + i] = start_line + i
				i += 1
			end

			push node.slice
		end

		def visit_alias_global_variable_node(node)
			emit node
		end

		def visit_alias_method_node(node)
			emit node
		end

		def visit_alternation_pattern_node(node)
			emit node
		end

		def visit_and_node(node)
			emit node
		end

		def visit_arguments_node(node)
			# Visit each argument, adding commas between them
			first = true
			node.child_nodes.each do |child|
				push ", " unless first
				first = false
				visit child
			end
		end

		def visit_array_node(node)
			emit node
		end

		def visit_array_pattern_node(node)
			emit node
		end

		def visit_assoc_node(node)
			# If the value contains a heredoc, visit key and value separately
			if contains_heredoc?(node.value)
				# Handle symbol keys with label syntax specially
				if node.key.is_a?(Prism::SymbolNode) && node.key.opening_loc.nil? && node.key.closing_loc
					# For label syntax (key:), emit just the value_loc and closing_loc
					emit node.key.value_loc
					emit node.key.closing_loc
					push " "
				else
					visit node.key
					# Check if it's a symbol key (ends with :) or needs =>
					if node.operator_loc
						emit node.operator_loc
					# else
						# push ": "
					end
				end
				visit node.value
			else
				emit node
			end
		end

		def visit_assoc_splat_node(node)
			emit node
		end

		def visit_back_reference_read_node(node)
			emit node
		end

		def visit_begin_node(node)
			emit node
		end

		def visit_block_argument_node(node)
			emit node
		end

		def visit_block_local_variable_node(node)
			emit node
		end

		def visit_block_node(node)
			emit node
		end

		def visit_block_parameter_node(node)
			emit node
		end

		def visit_block_parameters_node(node)
			emit node
		end

		def visit_break_node(node)
			emit node
		end

		def visit_call_and_write_node(node)
			emit node
		end

		def visit_call_node(node)
			# If this call has arguments that might contain heredocs, we need to handle them specially
			if node.arguments && contains_heredoc?(node.arguments)
				# Visit parts separately to handle heredocs
				visit node.receiver if node.receiver
				emit node.call_operator_loc if node.call_operator_loc

				# For [] calls, the message_loc includes the brackets and arguments,
				# so we should only emit the opening bracket to avoid duplication
				if node.name == :[]
					emit node.opening_loc
				else
					emit node.message_loc
					if node.opening_loc
						emit node.opening_loc
					else
						push " " if node.arguments
					end
				end

				visit node.arguments if node.arguments
				emit node.closing_loc if node.closing_loc
				# Only add space before regular blocks, not block arguments (&)
				push " " if node.block && !node.block.is_a?(Prism::BlockArgumentNode)
				visit node.block if node.block
			# If we have a BlockArgumentNode (&), we need to emit parts separately
			# because node.slice doesn't include the closing parenthesis
			elsif node.block.is_a?(Prism::BlockArgumentNode) && node.opening_loc
				visit node.receiver if node.receiver
				emit node.call_operator_loc if node.call_operator_loc
				emit node.message_loc
				emit node.opening_loc
				visit node.block
				emit node.closing_loc if node.closing_loc
			else
				emit node
			end
		end

		private def contains_heredoc?(node)
			case node
			when Prism::ArgumentsNode
				node.child_nodes.any? { |child| contains_heredoc?(child) }
			when Prism::StringNode
				node.opening_loc&.slice&.start_with?("<<")
			when Prism::InterpolatedStringNode
				node.opening_loc&.slice&.start_with?("<<")
			when Prism::HashNode, Prism::KeywordHashNode
				node.elements.any? { |element| contains_heredoc?(element) }
			when Prism::AssocNode
				contains_heredoc?(node.value)
			when Prism::LocalVariableWriteNode
				contains_heredoc?(node.value)
			else
				false
			end
		end

		def visit_call_operator_write_node(node)
			emit node
		end

		def visit_call_or_write_node(node)
			emit node
		end

		def visit_call_target_node(node)
			emit node
		end

		def visit_capture_pattern_node(node)
			emit node
		end

		def visit_case_match_node(node)
			emit node
		end

		def visit_case_node(node)
			emit node
		end

		def visit_class_node(node)
			emit node
		end

		def visit_class_variable_and_write_node(node)
			emit node
		end

		def visit_class_variable_operator_write_node(node)
			emit node
		end

		def visit_class_variable_or_write_node(node)
			emit node
		end

		def visit_class_variable_read_node(node)
			emit node
		end

		def visit_class_variable_target_node(node)
			emit node
		end

		def visit_class_variable_write_node(node)
			emit node
		end

		def visit_constant_and_write_node(node)
			emit node
		end

		def visit_constant_operator_write_node(node)
			emit node
		end

		def visit_constant_or_write_node(node)
			emit node
		end

		def visit_constant_path_and_write_node(node)
			emit node
		end

		def visit_constant_path_node(node)
			emit node
		end

		def visit_constant_path_operator_write_node(node)
			emit node
		end

		def visit_constant_path_or_write_node(node)
			emit node
		end

		def visit_constant_path_target_node(node)
			emit node
		end

		def visit_constant_path_write_node(node)
			emit node
		end

		def visit_constant_read_node(node)
			emit node
		end

		def visit_constant_target_node(node)
			emit node
		end

		def visit_constant_write_node(node)
			emit node
		end

		def visit_def_node(node)
			emit node
		end

		def visit_defined_node(node)
			emit node
		end

		def visit_else_node(node)
			emit node
		end

		def visit_embedded_statements_node(node)
			emit node
		end

		def visit_embedded_variable_node(node)
			emit node
		end

		def visit_ensure_node(node)
			emit node
		end

		def visit_false_node(node)
			emit node
		end

		def visit_find_pattern_node(node)
			emit node
		end

		def visit_flip_flop_node(node)
			emit node
		end

		def visit_float_node(node)
			emit node
		end

		def visit_for_node(node)
			emit node
		end

		def visit_forwarding_arguments_node(node)
			emit node
		end

		def visit_forwarding_parameter_node(node)
			emit node
		end

		def visit_forwarding_super_node(node)
			emit node
		end

		def visit_global_variable_and_write_node(node)
			emit node
		end

		def visit_global_variable_operator_write_node(node)
			emit node
		end

		def visit_global_variable_or_write_node(node)
			emit node
		end

		def visit_global_variable_read_node(node)
			emit node
		end

		def visit_global_variable_target_node(node)
			emit node
		end

		def visit_global_variable_write_node(node)
			emit node
		end

		def visit_hash_node(node)
			# If the hash contains heredocs, we need to visit elements individually
			if contains_heredoc?(node)
				emit node.opening_loc
				node.elements.each_with_index do |element, i|
					push ", " if i > 0
					visit element
				end
				emit node.closing_loc
			else
				emit node
			end
		end

		def visit_hash_pattern_node(node)
			emit node
		end

		def visit_if_node(node)
			emit node
		end

		def visit_imaginary_node(node)
			emit node
		end

		def visit_implicit_node(node)
			emit node
		end

		def visit_implicit_rest_node(node)
			emit node
		end

		def visit_in_node(node)
			emit node
		end

		def visit_index_and_write_node(node)
			emit node
		end

		def visit_index_operator_write_node(node)
			emit node
		end

		def visit_index_or_write_node(node)
			emit node
		end

		def visit_index_target_node(node)
			emit node
		end

		def visit_instance_variable_and_write_node(node)
			emit node
		end

		def visit_instance_variable_operator_write_node(node)
			emit node
		end

		def visit_instance_variable_or_write_node(node)
			emit node
		end

		def visit_instance_variable_read_node(node)
			emit node
		end

		def visit_instance_variable_target_node(node)
			emit node
		end

		def visit_instance_variable_write_node(node)
			# Check if the value is a call node with a block argument
			# This works around a Prism bug where the node's location doesn't include
			# the closing parenthesis when the call has a BlockArgumentNode
			if node.value.is_a?(Prism::CallNode) && 
			   node.value.block.is_a?(Prism::BlockArgumentNode) && 
			   node.value.closing_loc
				emit node.name_loc
				emit node.operator_loc
				push " "
				visit node.value
			else
				emit node
			end
		end

		def visit_integer_node(node)
			emit node
		end

		def visit_interpolated_match_last_line_node(node)
			emit node
		end

		def visit_interpolated_regular_expression_node(node)
			emit node
		end

		def visit_interpolated_string_node(node)
			# Heredocs cannot be emitted verbatim since they span multiple lines
			# with special syntax, so we convert them to regular strings
			if node.opening_loc&.slice&.start_with?("<<")
				push '"'
				node.parts.each do |part|
					case part
					when Prism::StringNode
						push part.unescaped.gsub('"', '\"').gsub("\n", '\n')
					when Prism::EmbeddedStatementsNode
						push '#{'
						visit part.statements
						push '}'
					end
				end
				push '"'
			else
				emit node
			end
		end

		def visit_interpolated_symbol_node(node)
			emit node
		end

		def visit_interpolated_x_string_node(node)
			emit node
		end

		def visit_it_local_variable_read_node(node)
			emit node
		end

		def visit_it_parameters_node(node)
			emit node
		end

		def visit_keyword_hash_node(node)
			# If the hash contains heredocs, we need to visit elements individually
			if contains_heredoc?(node)
				first = true
				node.elements.each do |element|
					push ", " unless first
					first = false
					visit element
				end
			else
				emit node
			end
		end

		def visit_keyword_rest_parameter_node(node)
			emit node
		end

		def visit_lambda_node(node)
			emit node
		end

		def visit_local_variable_and_write_node(node)
			emit node
		end

		def visit_local_variable_operator_write_node(node)
			emit node
		end

		def visit_local_variable_or_write_node(node)
			emit node
		end

		def visit_local_variable_read_node(node)
			emit node
		end

		def visit_local_variable_target_node(node)
			emit node
		end

		def visit_local_variable_write_node(node)
			# If the value contains a heredoc, visit parts separately
			if contains_heredoc?(node.value)
				emit node.name_loc
				emit node.operator_loc
				push " "
				visit node.value
			else
				emit node
			end
		end

		def visit_match_last_line_node(node)
			emit node
		end

		def visit_match_predicate_node(node)
			emit node
		end

		def visit_match_required_node(node)
			emit node
		end

		def visit_match_write_node(node)
			emit node
		end

		def visit_missing_node(node)
			emit node
		end

		def visit_module_node(node)
			emit node
		end

		def visit_multi_target_node(node)
			emit node
		end

		def visit_multi_write_node(node)
			emit node
		end

		def visit_next_node(node)
			emit node
		end

		def visit_nil_node(node)
			emit node
		end

		def visit_no_keywords_parameter_node(node)
			emit node
		end

		def visit_numbered_parameters_node(node)
			emit node
		end

		def visit_numbered_reference_read_node(node)
			emit node
		end

		def visit_optional_keyword_parameter_node(node)
			emit node
		end

		def visit_optional_parameter_node(node)
			emit node
		end

		def visit_or_node(node)
			emit node
		end

		def visit_parameters_node(node)
			emit node
		end

		def visit_parentheses_node(node)
			emit node
		end

		def visit_pinned_expression_node(node)
			emit node
		end

		def visit_pinned_variable_node(node)
			emit node
		end

		def visit_post_execution_node(node)
			emit node
		end

		def visit_pre_execution_node(node)
			emit node
		end

		def visit_program_node(node)
			emit node
		end

		def visit_range_node(node)
			emit node
		end

		def visit_rational_node(node)
			emit node
		end

		def visit_redo_node(node)
			emit node
		end

		def visit_regular_expression_node(node)
			emit node
		end

		def visit_required_keyword_parameter_node(node)
			emit node
		end

		def visit_required_parameter_node(node)
			emit node
		end

		def visit_rescue_modifier_node(node)
			emit node
		end

		def visit_rescue_node(node)
			emit node
		end

		def visit_rest_parameter_node(node)
			emit node
		end

		def visit_retry_node(node)
			emit node
		end

		def visit_return_node(node)
			emit node
		end

		def visit_self_node(node)
			emit node
		end

		def visit_shareable_constant_node(node)
			emit node
		end

		def visit_singleton_class_node(node)
			emit node
		end

		def visit_source_encoding_node(node)
			emit node
		end

		def visit_source_file_node(node)
			emit node
		end

		def visit_source_line_node(node)
			emit node
		end

		def visit_splat_node(node)
			emit node
		end

		def visit_statements_node(node)
			emit node
		end

		def visit_string_node(node)
			# Heredocs cannot be emitted verbatim since they span multiple lines
			# with special syntax, so we convert them to regular strings
			if node.opening_loc&.slice&.start_with?("<<")
				push node.unescaped.inspect
			else
				emit node
			end
		end

		def visit_super_node(node)
			emit node
		end

		def visit_symbol_node(node)
			emit node
		end

		def visit_true_node(node)
			emit node
		end

		def visit_undef_node(node)
			emit node
		end

		def visit_unless_node(node)
			emit node
		end

		def visit_until_node(node)
			emit node
		end

		def visit_when_node(node)
			emit node
		end

		def visit_while_node(node)
			emit node
		end

		def visit_x_string_node(node)
			emit node
		end

		def visit_yield_node(node)
			emit node
		end
	end
end
