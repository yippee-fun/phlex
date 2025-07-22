# frozen_string_literal: true

class Phlex::Compiler::Compactor < Refract::MutationVisitor
	visit Refract::StatementsNode do |node|
		queue = []
		results = []
		current_buffer = nil
		nil_context = false

		node.body.reverse_each { |n| queue << n }

		while (child_node = queue.pop)
			case child_node
			when Refract::StatementsNode
				child_node.body.reverse_each { |n| queue << n }
			when Phlex::Compiler::Concat
				if current_buffer
					current_buffer << child_node.node
					unless nil_context
						results << Refract::NilNode.new
						nil_context = true
					end
				else
					current_buffer = [child_node.node]
					results << Refract::ParenthesesNode.new(
						body: Refract::StatementsNode.new(
							body: [
								Refract::IfNode.new(
									inline: false,
									predicate: Refract::LocalVariableReadNode.new(
										name: :__phlex_should_render__
									),
									statements: Refract::StatementsNode.new(
										body: [
											Refract::CallNode.new(
												receiver: Refract::CallNode.new(
													name: :__phlex_buffer__,
												),
												name: :<<,
												arguments: Refract::ArgumentsNode.new(
													arguments: [
														Refract::InterpolatedStringNode.new(
															parts: current_buffer
														),
													]
												)
											),
										]
									)
								),
								Refract::NilNode.new,
							]
						)
					)
					nil_context = true
				end
			else
				resolved = visit(child_node)
				case resolved
				when Refract::StatementsNode
					resolved.body.reverse_each { |n| queue << n }
				else
					current_buffer = nil
					results << resolved
					nil_context = false
				end
			end
		end

		node.copy(
			body: results
		)
	end
end
