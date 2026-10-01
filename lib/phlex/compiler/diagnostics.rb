# frozen_string_literal: true

# Why parts of a file were left to the runtime: a method that couldn't be
# matched to the live one, or a call whose arguments or block the compiler
# doesn't handle. Collected while a file is compiled and returned by
# `Phlex::Compiler.explain`.
#
# Code the compiler refuses to compile, because it couldn't do so faithfully,
# raises instead when compiling, so the problem is seen rather than worked
# around silently. `explain` collects refusals like any other diagnostic.
class Phlex::Compiler::Diagnostics
	include Enumerable

	Diagnostic = Data.define(:path, :line, :message) do
		def to_s = "#{path}:#{line}: #{message}"
	end

	def initialize(path, strict: true)
		@path = path
		@strict = strict
		@diagnostics = []
	end

	# In file order, whichever pass reported them.
	def each(&)
		@diagnostics.each_with_index.sort_by { |diagnostic, index| [diagnostic.line || 0, index] }.map(&:first).each(&)
	end

	def report(node, message)
		@diagnostics << Diagnostic.new(path: @path, line: node&.start_line, message:)
	end

	def refuse(node, message)
		raise Phlex::Compiler::Error, Diagnostic.new(path: @path, line: node&.start_line, message:).to_s if @strict

		report(node, message)
	end
end
