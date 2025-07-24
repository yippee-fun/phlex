# frozen_string_literal: true

require "prism"
require "refract"

module Phlex::Compiler
	MAP = {}
	Error = Class.new(StandardError)

	def self.compile(component)
		path, line = Object.const_source_location(component.name)
		compile_file(path)
	end

	def self.compile_file(path)
		unless File.exist?(path)
			raise ArgumentError, "Can’t compile #{path} because it doesn’t exist."
		end

		require(path)

		source = File.read(path)
		tree = Prism.parse(source).value
		refract = Refract::Converter.new.visit(tree)

		last_line = source.count("\n")

		starting_line = last_line + 1

		results = FileCompiler.new(path).compile(refract)

		result = Refract::StatementsNode.new(
			body: results.map do |result|
				result.namespace.reverse_each.reduce(
					result.compiled_snippets
				) do |body, scope|
					scope.copy(
						body: Refract::StatementsNode.new(
							body: [body]
						)
					)
				end
			end
		)

		formatting_result = Refract::Formatter.new(starting_line:).format_node(result)

		MAP[path] = formatting_result.source_map

		puts formatting_result.source

		eval("# frozen_string_literal: true\n#{formatting_result.source}", TOPLEVEL_BINDING, path, starting_line - 1)
	end
end
