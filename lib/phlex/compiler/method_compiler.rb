# frozen_string_literal: true

require "prism"

module Phlex::Compiler
	class MethodCompiler < Prism::MutationCompiler
		def initialize(component)
			@component = component
			@current_buffer = nil
			@preamble = Set[]
		end

		def compile(node)
			result = visit(node)
			result.body&.body&.unshift(@preamble, statement("nil"))

			source, map = Phlex::Compiler::Formatter.new.format(result)
			source
		end

		def visit_call_node(node)
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

			clear_buffer
			super
		end

		def visit_class_node(node)
			node
		end

		def visit_module_node(node)
			node
		end

		def compile_standard_element(node, tag)
			[
				[
					buffer("<#{tag}"),
					*(
						if node.arguments
							visit_phlex_attributes(node.arguments)
						end
					),
					buffer(">"),
					*(
						if node.block
							[visit_phlex_block(node.block)]
						end
					),
					buffer("</#{tag}>"),
				],
			]
		end

		def visit_phlex_attributes(node)
			if node.arguments in [Prism::KeywordHashNode[elements: attributes]]
				literal_attributes = attributes.all? do |attribute|
					Prism::AssocNode === attribute && static_attribute_value_literal?(attribute)
				end

				if literal_attributes
					return buffer(Phlex::SGML::Attributes.generate_attributes(eval("{#{node.slice}}")))
				end
			end

			[
				:new_line,
				push("__render_attributes__("),
				node,
				push(")"),
			]
		end

		def visit_phlex_block(node)
			if Prism::BlockArgumentNode === node
				[push("__yield_content__("), node, push(")")]
			elsif output_block?(node)
				visit(node.body)
			elsif content_block?(node)
				content = node.body.body.first
				case content
				when Prism::StringNode
					buffer(Phlex::Escape.html_escape(content.unescaped))
				when Prism::InterpolatedStringNode
					compile_interpolated_string_node(content)
				else
					raise
				end
			else
				[
					statement("__yield_content__ do"),
					[node.body],
					statement("end"),
				]
			end
		end

		def visit_block_node(node)
			node.copy(
				body: compile_block_body_node(node.body)
			)
		end

		def compile_block_body_node(node)
			[
				statement("if #{self_local} == self"),
				visit(node),
				statement("else"),
				[[node]],
				statement("end"),
			]
		end

		def compile_interpolated_string_node(node)
			node.parts.map do |part|
				case part
				when Prism::StringNode
					buffer(Phlex::Escape.html_escape(part.unescaped))
				when Prism::EmbeddedVariableNode
					[
						buffer('#{'),
						buffer("::Phlex::Escape.html_escape(("),
						buffer(part.variable.slice),
						buffer(").to_s)}"),
					]
				when Prism::EmbeddedStatementsNode
					[
						buffer('#{'),
						buffer("::Phlex::Escape.html_escape(("),
						buffer(part.statements.slice, escape: false),
						buffer(").to_s)}"),
					]
				else
					raise Phlex::Compiler::Error, "Unexpected node type in InterpolatedStringNode: #{part.class}"
				end
			end
		end

		def compile_void_element(node, tag)
			[
				[
					buffer("<#{tag}"),
					*(
						if node.arguments
							visit_phlex_attributes(node.arguments)
						end
					),
					buffer(">"),
				],
			]
		end

		def compile_whitespace_helper(node)
			if node.block
				[
					buffer(" "),
					visit_phlex_block(node.block),
					buffer(" "),
				]
			else
				[
					buffer(" "),
				]
			end
		end

		def compile_doctype_helper(node)
			[
				buffer("<!doctype html>"),
			]
		end

		def compile_plain_helper(node)
			if node.arguments in [Prism::StringNode]
				[
					buffer(node.arguments.child_nodes.first.unescaped),
				]
			else
				@current_buffer = nil
				node
			end
		end

		def compile_fragment_helper(node)
			node.copy(
				block: compile_fragment_helper_block(node.block)
			)
		end

		def compile_fragment_helper_block(node)
			node.copy(
				body: [
					statement("__phlex_original_should_render__ = #{should_render_local}"),
					statement("#{should_render_local} = #{state_local}.should_render?"),
					visit(node.body),
					statement("#{should_render_local} = __phlex_original_should_render__"),
				]
			)
		end

		def compile_comment_helper(node)
			[
				buffer("<!-- "),
				visit_phlex_block(node.block),
				buffer(" -->"),
			]
		end

		def compile_raw_helper(node)
			clear_buffer
			node
		end

		private def statement(string)
			clear_buffer
			[
				:new_line,
				string,
				";",
			]
		end

		private def push(value)
			clear_buffer
			value
		end

		private def clear_buffer
			@current_buffer = nil
		end

		private def buffer(value, escape: true)
			if @current_buffer
				if escape
					@current_buffer << value.gsub('"', '\\"')
				else
					@current_buffer << value
				end
				nil
			else
				new_buffer = +""
				@current_buffer = new_buffer
				if escape
					new_buffer << value.gsub('"', '\\"')
				else
					new_buffer << value
				end

				[
					:new_line,
					"#{buffer_local} << \"",
					new_buffer,
					"\" if #{should_render_local}; nil;",
				]
			end
		end

		private def new_scope
			original_in_scope = @in_scope
			@in_scope = false
			yield
			@in_scope = original_in_scope
		end

		private def output_block?(node)
			node.body.body.any? do |child|
				Prism::CallNode === child && (standard_element?(child) || void_element?(child) || plain_helper?(child) || whitespace_helper?(child) || raw_helper?(child))
			end
		end

		private def content_block?(node)
			return false unless node.body.body.length == 1
			node.body.body.first in Prism::StringNode | Prism::InterpolatedStringNode
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
			when Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode, Prism::FloatNode, Prism::TrueNode, Prism::FalseNode, Prism::NilNode
				true
			when Prism::ArrayNode
				value.elements.all? { |n| static_token_value_literal?(n) }
			when Prism::HashNode
				value.elements.all? { |n| static_attribute_value_literal?(n) }
			when Prism::AssocNode
				(Prism::StringNode === value.key || Prism::SymbolNode === value.key) && static_attribute_value_literal?(value.value)
			when Prism::CallNode
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

		ALLOWED_OWNERS = [Phlex::SGML, Phlex::HTML, Phlex::SVG]
		private def own_method_without_scope?(node)
			ALLOWED_OWNERS.include?(@component.instance_method(node.name).owner)
		end

		private def extract_kwargs_from_string(string)
			eval("{#{string}}")
		end

		private def state_local
			@preamble << [:new_line, "__phlex_state__ = @_state;"]
			"__phlex_state__"
		end

		private def buffer_local
			@preamble << [:new_line, "__phlex_buffer__ = #{state_local}.buffer;"]
			"__phlex_buffer__"
		end

		private def self_local
			@preamble << [:new_line, "__phlex_self__ = self;"]
			"__phlex_self__"
		end

		private def should_render_local
			@preamble << [:new_line, "__phlex_should_render__ = #{state_local}.should_render?;"]
			"__phlex_should_render__"
		end
	end
end
