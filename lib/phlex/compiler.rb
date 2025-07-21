# frozen_string_literal: true

require "prism"
require "refract"

module Phlex::Compiler
	Error = Class.new(StandardError)

	class BufferPush
		def initialize(value, escape:)
			@value = value
			@escape = escape
			freeze
		end

		attr_reader :value, :escape
	end

	def self.compile(component)
		path, line = Object.const_source_location(component.name)
		return unless File.exist?(path)
		source = File.read(path)
		tree = Prism.parse(source).value
		refract = Refract::Converter.new.visit(tree)

		Compilation.new(component, path, line, source, refract).compile
	end
end
