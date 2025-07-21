# frozen_string_literal: true

module Phlex::Compiler
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
			result = FileCompiler.new(self).compile(@tree)

			result.compiled_snippets.each do |snippet|
				start_line = snippet.start_line

				namespaced = result.namespace.reverse_each.reduce(snippet) do |body, scope|
					start_line -= 1

					scope.copy(
						body: Refract::StatementsNode.new(
							body: [body]
						)
					)
				end

				source = Refract::Formatter.new.format_node(namespaced)

				redefine_method(
					source,
					start_line
				)
			end
		end

		def redefine_method(source, line)
			eval("# frozen_string_literal: true\n#{source}", TOPLEVEL_BINDING, @path, line - 1)
		end
	end
end
