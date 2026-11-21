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
		body = []

		flatten(node.body).each do |child|
			case child
			in Output::Append if Output::Append === body.last
				body[-1] = Output::Append.new(parts: body.last.parts + child.parts)
			in Output::Append
				body << child
			in Output::Enclosed
				body.concat(enclose(child))
			in Output::Opening
				body << chain(child.parts, read(child.buffer))
			else
				body << visit(child)
			end
		end

		node.copy(body: body.compact.map { |statement| (Output::Append === statement) ? append(statement.parts) : statement })
	end

	# Splices nested statements and enclosures that can't exit early into the
	# list. ASCII text at either end of an enclosure's body moves out of it, to
	# fuse with the text around it, since appending it can't fail or jump. An
	# enclosure whose body is then just another enclosure closes both at once.
	private def flatten(statements)
		statements.flat_map do |statement|
			case statement
			in nil then []
			in Refract::StatementsNode then flatten(statement.body)
			in Output::Enclosed if Output.static?(statement) then flatten(statement.body)
			in Output::Enclosed
				body = flatten(statement.body)
				leading = body.take_while { |child| ascii_text?(child) }
				rest = body.drop(leading.length)
				trailing = rest.reverse.take_while { |child| ascii_text?(child) }.reverse
				body = rest.take(rest.length - trailing.length)

				enclosed = case body
					in [Output::Enclosed => inner] if statement.closing.ascii_only? && inner.closing.ascii_only?
						inner.with(closing: inner.closing + statement.closing)
					else
						statement.with(body:)
				end

				[*leading, enclosed, *trailing]
			else [statement]
			end
		end
	end

	private def ascii_text?(statement)
		Output::Append === statement && statement.parts.all? { |part| Output::Literal === part && part.text.ascii_only? }
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
		parenthesized([if_node(should_render, [chain(parts, buffer)]), Refract::NilNode.new])
	end

	private def chain(parts, receiver)
		fuse(parts).reduce(receiver) { |chained, part| call(chained, :<<, lower(part, receiver)) }
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

	private def lower(part, receiver)
		case part
		in Output::Literal then string(part.text)
		in Output::Conditional | Output::Expression then part.node
		in Output::Guarded then guard(part, receiver)
		end
	end

	# The guard is an expression inside the append chain, so the opening tag's
	# text has already been appended when the closing text is.
	private def guard(part, receiver)
		done = @locals.fresh(:done)

		begin_node(
			[write(done, Refract::FalseNode.new), *part.statements, write(done, Refract::TrueNode.new), lower(part.result, receiver)],
			ensure_clause: ensure_node([unless_node(read(done), [call(receiver, :<<, string(part.closing))], inline: true)])
		)
	end
end
