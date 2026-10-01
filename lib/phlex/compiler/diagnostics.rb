# frozen_string_literal: true

# Why parts of a file were left to the runtime: a class that couldn't be
# resolved, a method that couldn't be matched to the live one, or a call
# whose arguments or block the compiler doesn't handle. Collected while a
# file is compiled and returned by `Phlex::Compiler.explain`.
class Phlex::Compiler::Diagnostics
	include Enumerable

	Diagnostic = Data.define(:path, :line, :message) do
		def to_s = "#{path}:#{line}: #{message}"
	end

	def initialize(path)
		@path = path
		@diagnostics = []
	end

	# In file order, whichever pass reported them.
	def each(&)
		@diagnostics.each_with_index.sort_by { |diagnostic, index| [diagnostic.line || 0, index] }.map(&:first).each(&)
	end

	def report(node, message)
		@diagnostics << Diagnostic.new(path: @path, line: node&.start_line, message:)
	end
end
