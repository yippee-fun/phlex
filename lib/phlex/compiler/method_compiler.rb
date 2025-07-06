# frozen_string_literal: true

class Phlex::Compiler::MethodCompiler < Prism::Visitor
	def initialize(compiler)
		@compiler = compiler
		@mutations = []
		@in_scope = true
	end

	def compile(node)
		visit_all(node.child_nodes)

		method_offset = node.location.start_offset
		source = @compiler.source.byteslice(method_offset, node.location.length)

		if @mutations.any?
			@mutations.sort_by!.with_index { |(pos), index| [pos, index] }

			index = 0
			ir = []

			@mutations.each do |(pos, len, val)|
				pos -= method_offset

				ir << source.byteslice(index, pos - index)
				ir << val

				index = pos + len
			end

			ir << source.byteslice(index, source.bytesize - index)

			new_source = +""

			chain = []
			ir.each_with_index do |part, index|
				case part
				in String
					if chain.length > 0 && !part.match?(/\A\s*\z/)
						flush_chain(ir, chain)
					end
				in [:buffer, String]
					chain << index
				end
			end

			flush_chain(ir, chain) if chain.length > 0

			new_source = ir.join

			puts new_source

			@compiler.component.redefine_compiled_method(new_source, @compiler.path, node.location.start_line)
		end
	end

	def visit_call_node(node)
		if nil == node.receiver && @in_scope
			if (tag = standard_element?(node))
				compile_standard_element(node, tag)
				return super
			elsif (tag = void_element?(node))
				compile_void_element(node, tag)
				return super
			end
		end

		new_scope { super }
	end

	def compile_standard_element(node, tag)
		if node.arguments
			if node.block
				compile_standard_element_with_arguments_and_block(node, tag)
			else
				compile_standard_element_with_arguments_and_no_block(node, tag)
			end
		else
			if node.block
				compile_standard_element_with_no_arguments_and_block(node, tag)
			else
				compile_standard_element_with_no_arguments_and_no_block(node, tag)
			end
		end
	end

	def compile_void_element(node, tag)
	end

	def compile_standard_element_with_arguments_and_block(node, tag)
	end

	def compile_standard_element_with_arguments_and_no_block(node, tag)
		@mutations << [
			node.message_loc.start_offset,
			0,
			[:buffer, "<#{tag}"],
		]

		@mutations << [
			node.message_loc.start_offset,
			node.message_loc.length,
			"__attributes__",
		]

		@mutations << [
			node.closing_loc.end_offset,
			0,
			[:buffer, "</#{tag}>"],
		]
	end

	def compile_standard_element_with_no_arguments_and_block(node, tag)
		@mutations << [
			node.message_loc.start_offset,
			node.message_loc.length,
			[:buffer, "<#{tag}>"],
		]

		@mutations << [
			node.block.opening_loc.start_offset,
			node.block.opening_loc.length,
			"",
		]

		compile_content_block(node.block)

		@mutations << [
			node.block.closing_loc.start_offset,
			node.block.closing_loc.length,
			[:buffer, "</#{tag}>"],
		]
	end

	def compile_standard_element_with_no_arguments_and_no_block(node, tag)
		@mutations << [
			node.location.start_offset,
			node.location.length,
			[:buffer, "<#{tag}></#{tag}>"],
		]
	end

	def compile_content_block(node)
		@mutations << [
			node.opening_loc.end_offset,
			0,
			"__yield_content__ {",
		]

		@mutations << [
			node.closing_loc.start_offset,
			0,
			"}",
		]
	end

	private def new_scope
		original_in_scope = @in_scope
		@in_scope = false
		yield
		@in_scope = original_in_scope
	end

	private def standard_element?(node)
		if (tag = Phlex::HTML::StandardElements.__registered_elements__[node.name]) &&
				(Phlex::HTML::StandardElements == @compiler.component.instance_method(node.name).owner)

			tag
		else
			false
		end
	end

	private def void_element?(node)
		if (tag = Phlex::HTML::VoidElements.__registered_elements__[node.name]) &&
				(Phlex::HTML::VoidElements == @compiler.component.instance_method(node.name).owner)

			tag
		else
			false
		end
	end

	private def flush_chain(ir, chain)
		output = +""

		chain.each do |index|
			_, str = ir[index]
			output << str
			ir[index] = ""
		end

		ir[chain[0]] = %(;@_state.buffer << "#{output}";)

		chain.clear
	end
end
