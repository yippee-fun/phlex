# frozen_string_literal: true

# Raised when a component can't be compiled faithfully, rather than
# compiling it in a way that would render differently.
class Phlex::Compiler::Error < StandardError
	include Phlex::Error
end
