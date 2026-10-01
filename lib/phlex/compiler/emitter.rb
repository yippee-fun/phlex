# frozen_string_literal: true

# Lowers the output nodes MethodCompiler left in a method's tree to Ruby.
# Each run of appends becomes one chain of `<<` on the buffer behind the
# render check, with adjacent literals fused, and each enclosure becomes an
# `ensure` that appends its closing text if the body exits early.
class Phlex::Compiler::Emitter < Refract::MutationVisitor
	include Phlex::Compiler::Builder

	Output = Phlex::Compiler::Output

	def initialize(locals)
		super()
		@locals = locals
	end

	visit Refract::StatementsNode do |node|
		queue = node.body.compact.reverse
		body = []

		while (child = queue.pop)
			case child
			in Refract::StatementsNode
				child.body.compact.reverse_each { |grandchild| queue << grandchild }
			in Output::Enclosed if Output.static?(child)
				child.body.reverse_each { |grandchild| queue << grandchild }
			in Output::Append if Output::Append === body.last
				body[-1] = Output::Append.new(parts: body.last.parts + child.parts)
			in Output::Append
				body << child
			in Output::Enclosed
				body.concat(enclose(child))
			else
				body << visit(child)
			end
		end

		node.copy(body: body.compact.map { |statement| (Output::Append === statement) ? append(statement.parts) : statement })
	end

	private def enclose(node)
		done = @locals.fresh(:done)

		[
			write(done, Refract::FalseNode.new),
			begin_node(
				[*visit(statements(node.body)).body, write(done, Refract::TrueNode.new)],
				ensure_clause: ensure_node([unless_node(read(done), [append([Output::Literal.new(node.closing)])])])
			),
		]
	end

	# Each part is appended in its own `<<` so that if one raises, everything
	# before it has already reached the buffer, as at runtime. The whole
	# statement evaluates to nil, like the element methods it replaces.
	private def append(parts)
		chain = fuse(parts).reduce(buffer) { |receiver, part| call(receiver, :<<, lower(part)) }

		parenthesized([if_node(should_render, [chain]), Refract::NilNode.new])
	end

	private def fuse(parts)
		parts.each_with_object([]) do |part, fused|
			if Output::Literal === part && Output::Literal === fused.last
				fused[-1] = Output::Literal.new(fused.last.text + part.text)
			else
				fused << part
			end
		end
	end

	private def lower(part)
		case part
		in Output::Literal then string(part.text)
		in Output::Conditional | Output::Expression then part.node
		in Output::Guarded then guard(part)
		end
	end

	# The guard is an expression inside the append chain, so the opening tag's
	# text has already been appended when the closing text is.
	private def guard(part)
		done = @locals.fresh(:done)

		begin_node(
			[write(done, Refract::FalseNode.new), *part.statements, write(done, Refract::TrueNode.new), lower(part.result)],
			ensure_clause: ensure_node([unless_node(read(done), [call(buffer, :<<, string(part.closing))], inline: true)])
		)
	end
end
