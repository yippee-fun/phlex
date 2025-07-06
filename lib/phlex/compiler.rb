# frozen_string_literal: true

require "prism"

class Phlex::Compiler
	def self.compile(component)
		path, line = Object.const_source_location(component.name)
		return unless File.exist?(path)
		source = File.read(path)
		tree = Prism.parse(source).value
		new(component, path, line, source, tree).compile
	end

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
end
