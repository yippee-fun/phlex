# frozen_string_literal: true

# What a compiled method appends to the buffer, before it's lowered to Ruby.
# MethodCompiler leaves these in the method's Refract tree where the output
# goes, and the Emitter replaces each run of them with one guarded append.
module Phlex::Compiler::Output
	# Text known at compile time.
	Literal = Data.define(:text)

	# A conditional choosing between literal texts whose predicate can't raise,
	# so it can't exit early.
	Conditional = Data.define(:node)

	# A Ruby expression that evaluates to the text to append, and may raise.
	Expression = Data.define(:node)

	# Statements that serialise attributes into locals, then the part to
	# append, with the closing text appended instead if the statements exit
	# early. The runtime closes an opening tag however serialisation exits.
	Guarded = Data.define(:statements, :result, :closing)

	# Stands in for a statement in the method's tree until it's emitted.
	module Statement
		def start_line = nil
		def accept(visitor) = self
	end

	# Parts appended to the buffer in order.
	Append = Data.define(:parts) do
		include Statement

		def static? = parts.all? { |part| part in Literal | Conditional }
	end

	# Statements whose output is followed by the closing text however they
	# exit, unless none of it can exit early.
	Enclosed = Data.define(:body, :closing) do
		include Statement
	end

	# Whether the statements can only append text that's known not to raise
	# or jump, so they need no guard.
	def self.static?(node)
		case node
		in Array then node.all? { |child| static?(child) }
		in Append then node.static?
		in Enclosed then static?(node.body)
		in Refract::StatementsNode then static?(node.body)
		else false
		end
	end
end
