# frozen_string_literal: true

module Phlex::Compiler
	class VerbatimFormatter < Prism::BasicVisitor
		def initialize
			@buffer = []
		end

		def push(string)
			@buffer << string
		end

		def emit(node)
			push node.slice if node
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
			emit node
		end

		def visit_array_node(node)
			emit node
		end

		def visit_array_pattern_node(node)
			emit node
		end

		def visit_assoc_node(node)
			emit node
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
			emit node
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
			emit node
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
			emit node
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
			emit node
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
			emit node
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
			emit node
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
			emit node
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
