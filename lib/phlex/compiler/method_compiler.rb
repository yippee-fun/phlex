# frozen_string_literal: true

require "prism"

module Phlex::Compiler
	class MethodCompiler < Prism::MutationCompiler
		def initialize(component)
			@component = component
			@current_buffer = nil
		end

		def compile(node)
			result = visit(node)
			result.body&.body&.unshift(
				proc do |f|
					f.statement do
						f.push "__phlex_buffer__ = @_state.buffer; nil"
					end
					f.statement do
						f.push "__phlex_me__ = self; nil"
					end
				end
			)

			Phlex::Compiler::Formatter.new.format(result)
		end

		def visit_call_node(node)
			if nil == node.receiver
				if (tag = standard_element?(node))
					return compile_standard_element(node, tag)
				elsif (tag = void_element?(node))
					return compile_void_element(node, tag)
				end
			end

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
				result = attributes.all? { |attribute| attribute in Prism::AssocNode[key: Prism::SymbolNode, value: Prism::StringNode] }
				if result
					return buffer(Phlex::HTML.allocate.__send__(:__attributes__, eval("{#{node.slice}}")))
				end
			end

			[
				ensure_new_line,
				push("__render_attributes__("),
				node,
				push(")"),
			]
		end

		def visit_phlex_block(node)
			if output_block?(node)
				visit(node.body)
			elsif content_block?(node)
				content = node.body.body.first
				case content
				when Prism::StringNode
					buffer(Phlex::Escape.html_escape(content.unescaped))
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
				body: [
					statement("if __phlex_me__ == self"),
					visit(node.body),
					statement("else"),
					[[node.body]],
					statement("end"),
				]
			)
		end

		def compile_void_element(node, tag)
		end

		private def ensure_new_line
			proc(&:ensure_new_line)
		end

		private def new_line
			@current_buffer = nil

			proc(&:new_line)
		end

		private def statement(string)
			@current_buffer = nil

			proc do |f|
				f.statement do
					f.push string
				end
			end
		end

		private def push(value)
			@current_buffer = nil

			proc do |f|
				f.push value
			end
		end

		private def buffer(value)
			if @current_buffer
				@current_buffer << value
				nil
			else
				new_buffer = +""
				@current_buffer = new_buffer
				new_buffer << value

				proc do |f|
					f.statement do
						f.push "__phlex_buffer__ << \"#{new_buffer.gsub('"', '\\"')}\"; nil"
					end
				end
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
				Prism::CallNode === child && (standard_element?(child) || void_element?(child))
			end
		end

		private def content_block?(node)
			return false unless node.body.body.length == 1
			node.body.body.first in Prism::StringNode
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

		private def own_method_without_scope?(node)
			# TODO: Should return true for things like `capture`
			false
		end

		private def extract_kwargs_from_string(string)
			eval("{#{string}}")
		end
	end
end
