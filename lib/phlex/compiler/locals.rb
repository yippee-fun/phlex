# frozen_string_literal: true

# Names for the locals compiled code introduces. They all start with
# `__phlex_`, and a method that already uses such a name isn't compiled.
class Phlex::Compiler::Locals
	STATE = :__phlex_state__
	SELF = :__phlex_self__
	EXCEPTION = :__phlex_exception__

	def initialize
		@count = 0
	end

	def fresh(purpose)
		:"__phlex_#{purpose}_#{@count += 1}__"
	end
end
