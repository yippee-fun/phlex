# frozen_string_literal: true

module Phlex::Compiler
	MAP = {}

	class Compilation
		def initialize(component, path, line, source, tree)
			@component = component
			@path = path
			@line = line
			@source = source
			@tree = tree
			freeze
		end

		attr_reader :component, :line, :source, :path

		def compile
			last_line = @source.count("\n")

			result = FileCompiler.new(self).compile(@tree)

			namespaced = result.namespace.reverse_each.reduce(
				result.compiled_snippets
			) do |body, scope|
				scope.copy(
					body: Refract::StatementsNode.new(
						body: [body]
					)
				)
			end

			formatting_result = Refract::Formatter.new(starting_line: last_line).format_node(namespaced)

			MAP[@path] = formatting_result.source_map

			redefine(
				formatting_result.source,
				last_line
			)
		end

		def redefine(source, line)
			eval("# frozen_string_literal: true\n#{source}", TOPLEVEL_BINDING, @path, line - 1)
		end
	end
end
