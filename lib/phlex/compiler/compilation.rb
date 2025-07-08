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
			FileCompiler.new(self).compile(@tree)
		end

		def redefine_method(source, line)
			@component.class_eval("# frozen_string_literal: true\n#{source}", @path, line - 1)
		end
	end
end
