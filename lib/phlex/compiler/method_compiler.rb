# frozen_string_literal: true

require "prism"

module Phlex::Compiler
	class MethodCompiler < Refract::MutationVisitor
		def initialize(component)
			super()
			@component = component
			@current_buffer = nil
			@preamble = []
		end

		def compile(node)
			result = visit(node)

			Refract::Formatter.new.format_node(result)
		end

		def around_visit(node)
			result = super

			# We want to clear the buffer when there’s a node that isn’t a statements node,
			# but we should ignore nils, which are usually other buffers.
			if result
				unless Refract::StatementsNode === result
					clear_buffer
				end
			end

			result
		end

		visit Refract::ClassNode do |node|
			node
		end

		visit Refract::ModuleNode do |node|
			node
		end

		visit Refract::DefNode do |node|
			if @stack.size == 1
				node.copy(
					body: Refract::StatementsNode.new(
						body: [
							Refract::StatementsNode.new(
								body: @preamble
							),
							Refract::NilNode.new,
							visit(node.body),
						]
					)
				)
			else
				node
			end
		end

		visit Refract::CallNode do |node|
			if nil == node.receiver
				if (tag = standard_element?(node))
					return compile_standard_element(node, tag)
				elsif (tag = void_element?(node))
					return compile_void_element(node, tag)
				elsif whitespace_helper?(node)
					return compile_whitespace_helper(node)
				elsif doctype_helper?(node)
					return compile_doctype_helper(node)
				elsif plain_helper?(node)
					return compile_plain_helper(node)
				elsif fragment_helper?(node)
					return compile_fragment_helper(node)
				elsif comment_helper?(node)
					return compile_comment_helper(node)
				elsif raw_helper?(node)
					return compile_raw_helper(node)
				end
			end

			super(node)
		end

		visit Refract::BlockNode do |node|
			node.copy(
				body: compile_block_body_node(
					node.body
				)
			)
		end

		def compile_standard_element(node, tag)
			node => Refract::CallNode

			Refract::StatementsNode.new(
				body: [
					buffer("<#{tag}"),
					*(
						if node.arguments
							compile_phlex_attributes(node.arguments)
						end
					),
					buffer(">"),
					*(
						if node.block
							compile_phlex_block(node.block)
						end
					),
					buffer("</#{tag}>"),
				]
			)
		end

		def compile_void_element(node, tag)
			node => Refract::CallNode

			Refract::StatementsNode.new(
				body: [
					buffer("<#{tag}"),
					*(
						if node.arguments
							compile_phlex_attributes(node.arguments)
						end
					),
					buffer(">"),
				]
			)
		end

		def compile_phlex_attributes(node)
			arguments = node.arguments

			if arguments.size == 1 && Refract::KeywordHashNode === (first_argument = arguments[0])
				attributes = first_argument.elements
				literal_attributes = attributes.all? do |attribute|
					Refract::AssocNode === attribute && static_attribute_value_literal?(attribute)
				end

				if literal_attributes
					return buffer(
						Phlex::SGML::Attributes.generate_attributes(
							eval(
								"{#{Refract::Formatter.new.format_node(node)}}"
							)
						)
					)
				end

				clear_buffer

				Refract::CallNode.new(
					name: :__render_attributes__,
					arguments: Refract::ArgumentsNode.new(
						arguments: [
							node,
						]
					)
				)
			end
		end

		def compile_phlex_block(node)
			case node
			when Refract::BlockNode
				if output_block?(node)
					return visit(node.body)
				elsif static_content_block?(node)
					content = node.body.body.first
					case content
					when Refract::StringNode, Refract::SymbolNode
						return buffer(Phlex::Escape.html_escape(content.unescaped))
					when Refract::InterpolatedStringNode
						return compile_interpolated_string_node(content)
					when Refract::NilNode
						return nil
					else
						raise
					end
				end
			end

			clear_buffer
			Refract::CallNode.new(
				name: :__yield_content__,
				block: node
			)
		end

		def compile_block_body_node(node)
			node => Refract::StatementsNode

			Refract::StatementsNode.new(
				body: [
					Refract::IfNode.new(
						inline: false,
						predicate: Refract::CallNode.new(
							receiver: Refract::SelfNode.new,
							name: :==,
							arguments: Refract::ArgumentsNode.new(
								arguments: [
									Refract::LocalVariableReadNode.new(
										name: self_local
									),
								]
							)
						),
						statements: Refract::StatementsNode.new(
							body: node.body.map { |n| visit(n) }
						),
						subsequent: Refract::ElseNode.new(
							statements: node
						)
					),
				]
			)
		end

		def compile_interpolated_string_node(node)
			node => Refract::InterpolatedStringNode

			Refract::StatementsNode.new(
				body: node.parts.map do |part|
					case part
					when Refract::StringNode
						buffer(Phlex::Escape.html_escape(part.unescaped))
					when Refract::EmbeddedVariableNode
						interpolate(part.variable)
					when Refract::EmbeddedStatementsNode
						interpolate(part.statements)
					else
						raise Phlex::Compiler::Error, "Unexpected node type in InterpolatedStringNode: #{part.class}"
					end
				end
			)
		end

		def compile_whitespace_helper(node)
			node => Refract::CallNode

			if node.block
				Refract::StatementsNode.new(
					body: [
						buffer(" "),
						compile_phlex_block(node.block),
						buffer(" "),
					]
				)
			else
				buffer(" ")
			end
		end

		def compile_doctype_helper(node)
			node => Refract::CallNode

			buffer("<!doctype html>")
		end

		def compile_plain_helper(node)
			node => Refract::CallNode

			if node.arguments in [Refract::StringNode]
				buffer(node.arguments.arguments.first.unescaped)
			else
				node
			end
		end

		def compile_fragment_helper(node)
			node => Refract::CallNode

			node.copy(
				block: compile_fragment_helper_block(node.block)
			)
		end

		def compile_fragment_helper_block(node)
			node => Refract::BlockNode

			node.copy(
				body: Refract::StatementsNode.new(
					body: [
						Refract::LocalVariableWriteNode.new(
							name: :__phlex_original_should_render__,
							value: Refract::LocalVariableReadNode.new(
								name: should_render_local
							)
						),
						Refract::LocalVariableWriteNode.new(
							name: should_render_local,
							value: Refract::CallNode.new(
								receiver: Refract::LocalVariableReadNode.new(
									name: state_local
								),
								name: :should_render?
							)
						),
						visit(node.body),
						Refract::LocalVariableWriteNode.new(
							name: should_render_local,
							value: Refract::LocalVariableReadNode.new(
								name: :__phlex_original_should_render__
							)
						),
					]
				)
			)
		end

		def compile_comment_helper(node)
			node => Refract::CallNode

			Refract::StatementsNode.new(
				body: [
					buffer("<!-- "),
					compile_phlex_block(node.block),
					buffer(" -->"),
				]
			)
		end

		def compile_raw_helper(node)
			node => Refract::CallNode

			node
		end

		private def buffer(value)
			if @current_buffer
				@current_buffer << Refract::StringNode.new(
					unescaped: value
				)

				nil
			else
				new_buffer = [
					Refract::StringNode.new(
						unescaped: value
					),
				]

				@current_buffer = new_buffer

				Refract::IfNode.new(
					inline: false,
					predicate: Refract::LocalVariableReadNode.new(
						name: should_render_local
					),
					statements: Refract::StatementsNode.new(
						body: [
							Refract::CallNode.new(
								receiver: Refract::CallNode.new(
									name: buffer_local,
								),
								name: :<<,
								arguments: Refract::ArgumentsNode.new(
									arguments: [
										Refract::InterpolatedStringNode.new(
											parts: new_buffer
										),
									]
								)
							),
						]
					)
				)
			end
		end

		private def interpolate(statements, escape: true)
			embedded_statement = Refract::EmbeddedStatementsNode.new(
				statements: Refract::StatementsNode.new(
					body: [
						Refract::CallNode.new(
							receiver: Refract::ConstantPathNode.new(
								parent: Refract::ConstantPathNode.new(
									name: "Phlex"
								),
								name: "Escape"
							),
							name: :html_escape,
							arguments: Refract::ArgumentsNode.new(
								arguments: [
									Refract::CallNode.new(
										receiver: Refract::ParenthesesNode.new(
											body: statements
										),
										name: :to_s
									),
								]
							)
						),
					]
				)
			)

			if @current_buffer
				@current_buffer << embedded_statement

				nil
			else
				new_buffer = [embedded_statement]

				@current_buffer = new_buffer

				Refract::IfNode.new(
					predicate: Refract::LocalVariableReadNode.new(
						name: should_render_local
					),
					statements: Refract::StatementsNode.new(
						body: [
							Refract::CallNode.new(
								receiver: Refract::CallNode.new(
									name: buffer_local,
								),
								name: :<<,
								arguments: Refract::ArgumentsNode.new(
									arguments: [
										Refract::InterpolatedStringNode.new(
											parts: new_buffer
										),
									]
								)
							),
						]
					)
				)
			end
		end

		private def clear_buffer
			@current_buffer = nil
		end

		private def output_block?(node)
			node.body.body.any? do |child|
				Refract::CallNode === child && (
					standard_element?(child) ||
					void_element?(child) ||
					plain_helper?(child) ||
					whitespace_helper?(child) ||
					raw_helper?(child)
				)
			end
		end

		private def static_content_block?(node)
			return false unless node.body.body.length == 1
			node.body.body.first in Refract::StringNode | Refract::InterpolatedStringNode | Refract::SymbolNode | Refract::NilNode
		end

		private def standard_element?(node)
			if (tag = Phlex::HTML::StandardElements.__registered_elements__[node.name]) &&
					(Phlex::HTML::StandardElements == @component.instance_method(node.name).owner)

				tag
			else
				false
			end
		end

		private def void_element?(node)
			if (tag = Phlex::HTML::VoidElements.__registered_elements__[node.name]) &&
					(Phlex::HTML::VoidElements == @component.instance_method(node.name).owner)

				tag
			else
				false
			end
		end

		private def static_attribute_value_literal?(value)
			case value
			when Refract::SymbolNode, Refract::StringNode, Refract::IntegerNode, Refract::FloatNode, Refract::TrueNode, Refract::FalseNode, Refract::NilNode
				true
			when Refract::ArrayNode
				value.elements.all? { |n| static_token_value_literal?(n) }
			when Refract::HashNode
				value.elements.all? { |n| static_attribute_value_literal?(n) }
			when Refract::AssocNode
				(Refract::StringNode === value.key || Refract::SymbolNode === value.key) && static_attribute_value_literal?(value.value)
			when Refract::CallNode
				if value in { receiver: Prism::ConstantReadNode[name: :Set]| Prism::ConstantPathNode[name: :Set, parent: nil], name: :[] }
					value.arguments.arguments.all? { |n| static_token_value_literal?(n) }
				else
					false
				end
			else
				false
			end
		end

		private def static_token_value_literal?(value)
			case value
			when Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode, Prism::FloatNode, Prism::NilNode
				true
			when Prism::ArrayNode
				value.elements.all? { |n| static_token_value_literal?(n) }
			else
				false
			end
		end

		private def whitespace_helper?(node)
			node.name == :whitespace && own_method_without_scope?(node)
		end

		private def doctype_helper?(node)
			node.name == :doctype && own_method_without_scope?(node)
		end

		private def plain_helper?(node)
			node.name == :plain && own_method_without_scope?(node)
		end

		private def fragment_helper?(node)
			node.name == :fragment && own_method_without_scope?(node)
		end

		private def comment_helper?(node)
			node.name == :comment && own_method_without_scope?(node)
		end

		private def raw_helper?(node)
			node.name == :raw && own_method_without_scope?(node)
		end

		ALLOWED_OWNERS = Set[Phlex::SGML, Phlex::HTML, Phlex::SVG]
		private def own_method_without_scope?(node)
			ALLOWED_OWNERS.include?(@component.instance_method(node.name).owner)
		end

		private def state_local
			:__phlex_state__.tap do |local|
				unless @state_local_set
					@preamble << Refract::LocalVariableWriteNode.new(
						name: local,
						value: Refract::InstanceVariableReadNode.new(
							name: :@_state
						)
					)

					@state_local_set = true
				end
			end
		end

		private def buffer_local
			:__phlex_buffer__.tap do |local|
				unless @buffer_local_set
					@preamble << Refract::LocalVariableWriteNode.new(
						name: local,
						value: Refract::CallNode.new(
							receiver: Refract::LocalVariableReadNode.new(
								name: state_local
							),
							name: :buffer,
						)
					)

					@buffer_local_set = true
				end
			end
		end

		private def self_local
			:__phlex_self__.tap do |local|
				unless @self_local_set
					@preamble << Refract::LocalVariableWriteNode.new(
						name: local,
						value: Refract::SelfNode.new
					)

					@self_local_set = true
				end
			end
		end

		private def should_render_local
			:__phlex_should_render__.tap do |local|
				unless @should_render_local_set
					@preamble << Refract::LocalVariableWriteNode.new(
						name: :__phlex_should_render__,
						value: Refract::CallNode.new(
							receiver: Refract::LocalVariableReadNode.new(
								name: state_local
							),
							name: :should_render?
						)
					)

					@should_render_local_set = true
				end
			end
		end
	end
end
