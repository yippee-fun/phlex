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
		@flattened = {}.compare_by_identity
		@quiet = {}.compare_by_identity
		@expected_values = {}.compare_by_identity
	end

	visit Refract::StatementsNode do |node|
		body = []

		expect(flatten(node.body)).each do |child|
			case child
			in Output::Append if Output::Append === body.last
				body[-1] = Output::Append.new(parts: body.last.parts + child.parts)
			in Output::Append
				body << child
			in Output::Enclosed
				body.concat(enclose(child))
			in Output::Opening
				body.concat(appends(child.parts, read(child.buffer)))
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
			in Output::Enclosed then @flattened.fetch(statement) { @flattened[statement] = flatten_enclosed(statement) }
			else [statement]
			end
		end
	end

	# The same enclosure is flattened again as each list around it is, so what
	# it flattens to is kept, and flattening that gives it back unchanged.
	private def flatten_enclosed(statement)
		body = flatten(statement.body)
		leading = body.take_while { |child| ascii_text?(child) }
		rest = body.drop(leading.length)
		trailing = rest.reverse.take_while { |child| ascii_text?(child) }.reverse
		body = rest.take(rest.length - trailing.length)

		enclosed = case body
			in [Output::Enclosed => inner] if statement.closing.ascii_only? && inner.closing.ascii_only?
				inner.with(closing: inner.closing + statement.closing, opened: inner.opened && statement.opened)
			else
				statement.with(body:)
		end

		@flattened[enclosed] = [enclosed]
		[*leading, enclosed, *trailing]
	end

	# A run of output that runs nothing else, with expected values in it, is
	# emitted twice: as static text for when every value is as expected, and
	# as it would be otherwise. Nothing in the run can change a value between
	# where it's tested and where it's rendered. Values read by constant go
	# into locals before the run. An enclosure whose opening text wasn't
	# static is never part of a run, since if a read raised it would have to
	# close something already appended: it expects its own values inside.
	private def expect(statements)
		quiet = statements.map { |statement| quiet?(statement) }

		statements.zip(quiet).slice_when { |(_, a), (_, b)| a != b }.flat_map do |pairs|
			run = pairs.map(&:first)
			next run unless pairs.first[1]

			expected = run.flat_map { |statement| expected_values(statement) }
			next run if expected.empty?

			[*expected.flat_map(&:reads), if_node(all(expected.map(&:guard)), expected(run, true), else_body: expected(run, false))]
		end
	end

	# Balanced, so a long run doesn't nest the predicate as deeply as it's long.
	private def all(guards)
		return guards.first if guards.one?

		half = guards.length / 2
		parenthesized([Refract::AndNode.new(left: all(guards.take(half)), operator: "&&", right: all(guards.drop(half)))])
	end

	private def quiet?(statement)
		case statement
		in Output::Expected then true
		in Output::Append then statement.static?
		in Output::Enclosed then @quiet.fetch(statement) { @quiet[statement] = statement.opened && flatten(statement.body).all? { |child| quiet?(child) } }
		else false
		end
	end

	private def expected_values(statement)
		case statement
		in Output::Expected then [statement]
		in Output::Enclosed then @expected_values.fetch(statement) { @expected_values[statement] = flatten(statement.body).flat_map { |child| expected_values(child) } }
		else []
		end
	end

	private def expected(statements, holds)
		statements.flat_map do |statement|
			case statement
			in Output::Expected then holds ? [Output::Append.new(parts: [Output::Literal.new(statement.text)])] : statement.otherwise
			in Output::Enclosed then [statement.with(body: expected(flatten(statement.body), holds))]
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
		parenthesized([if_node(should_render, appends(parts, buffer)), Refract::NilNode.new])
	end

	# One chain for each run of parts, and a choice of appends for each Choice.
	private def appends(parts, receiver)
		parts.slice_when { |a, b| Output::Choice === a || Output::Choice === b }.map do |run|
			case run
			in [Output::Choice => choice]
				if_node(
					read(choice.escaped),
					[chain([Output::Literal.new(choice.prefix), Output::Expression.new(read(choice.escaped)), Output::Literal.new(choice.suffix)], receiver)],
					else_body: [call(receiver, :<<, read(choice.text))]
				)
			else
				chain(run, receiver)
			end
		end
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
