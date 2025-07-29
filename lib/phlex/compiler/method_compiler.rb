# frozen_string_literal: true

require "prism"

module Phlex::Compiler
	Concat = Data.define(:node) do
		def start_line = nil
		def accept(visitor) = self
	end

	class MethodCompiler < Refract::MutationVisitor
		def initialize(component)
			super()
			@component = component
			@preamble = []
			@optimized = false
		end

		def compile(node)
			tree = visit(node)

			if @optimized
				Compactor.new.visit(
					tree
				)
			else
				nil
			end
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
					body: Refract::BeginNode.new(
						statements: Refract::StatementsNode.new(
							body: [
								Refract::StatementsNode.new(
									body: @preamble
								),
								Refract::NilNode.new,
								visit(node.body),
							]
						),
						rescue_clause: Refract::RescueNode.new(
							exceptions: [],
							reference: Refract::LocalVariableTargetNode.new(
								name: :__phlex_exception__
							),
							statements: Refract::StatementsNode.new(
								body: [
									Refract::CallNode.new(
										receiver: Refract::ConstantReadNode.new(
											name: :Kernel
										),
										name: :raise,
										arguments: Refract::ArgumentsNode.new(
											arguments: [
												Refract::CallNode.new(
													name: :__map_exception__,
													arguments: Refract::ArgumentsNode.new(
														arguments: [
															Refract::LocalVariableReadNode.new(
																name: :__phlex_exception__
															),
														]
													)
												),
											]
										)
									),
								]
							),
							subsequent: nil
						),
						else_clause: nil,
						ensure_clause: nil
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
			if node.body
				node.copy(
					body: compile_block_body_node(
						node.body
					)
				)
			else
				node
			end
		end

		def compile_standard_element(node, tag)
			node => Refract::CallNode

			Refract::StatementsNode.new(
				body: [
					raw("<#{tag}"),
					*(
						if node.arguments
							compile_phlex_attributes(node.arguments)
						end
					),
					raw(">"),
					*(
						if node.block
							compile_phlex_block(node.block)
						end
					),
					raw("</#{tag}>"),
				]
			)
		end

		def compile_void_element(node, tag)
			node => Refract::CallNode

			Refract::StatementsNode.new(
				body: [
					raw("<#{tag}"),
					*(
						if node.arguments
							compile_phlex_attributes(node.arguments)
						end
					),
					raw(">"),
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
					return raw(
						Phlex::SGML::Attributes.generate_attributes(
							eval(
								"{#{Refract::Formatter.new.format_node(node).source}}",
								TOPLEVEL_BINDING
							)
						)
					)
				end

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
						return plain(content.unescaped)
					when Refract::InterpolatedStringNode
						return compile_interpolated_string_node(content)
					when Refract::NilNode
						return nil
					else
						raise
					end
				end
			end

			Refract::CallNode.new(
				name: :__yield_content__,
				block: node
			)
		end

		def compile_block_body_node(node)
			node => Refract::StatementsNode | Refract::BeginNode

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
						plain(part.unescaped)
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
						raw(" "),
						compile_phlex_block(node.block),
						raw(" "),
					]
				)
			else
				raw(" ")
			end
		end

		def compile_doctype_helper(node)
			node => Refract::CallNode

			raw("<!doctype html>")
		end

		def compile_plain_helper(node)
			node => Refract::CallNode

			if node.arguments.arguments in [Refract::StringNode]
				raw(node.arguments.arguments.first.unescaped)
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
					raw("<!-- "),
					compile_phlex_block(node.block),
					raw(" -->"),
				]
			)
		end

		def compile_raw_helper(node)
			node => Refract::CallNode
			node
		end

		private def plain(value)
			value => String
			raw(Phlex::Escape.html_escape(value))
		end

		private def raw(value)
			value => String

			buffer(
				Refract::StringNode.new(
					unescaped: value
				)
			)
		end

		private def interpolate(statements)
			buffer(
				Refract::EmbeddedStatementsNode.new(
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
			)
		end

		private def buffer(node)
			@optimized = true
			node => Refract::StringNode | Refract::EmbeddedStatementsNode

			should_render_local
			buffer_local

			Refract::StatementsNode.new(
				body: [
					Concat.new(
						node
					),
				]
			)
		end

		private def output_block?(node)
			node.body&.body&.any? do |child|
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
			return false unless node.body&.body&.length == 1
			node.body.body.first in Refract::StringNode | Refract::InterpolatedStringNode | Refract::SymbolNode | Refract::NilNode
		end

		private def standard_element?(node)
			if (tag = Phlex::HTML::StandardElements.__registered_elements__[node.name]) &&
					(Phlex::HTML::StandardElements == Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name).owner)

				tag
			else
				false
			end
		end

		private def void_element?(node)
			if (tag = Phlex::HTML::VoidElements.__registered_elements__[node.name]) &&
					(Phlex::HTML::VoidElements == Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name).owner)

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
			ALLOWED_OWNERS.include?(Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name).owner)
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
