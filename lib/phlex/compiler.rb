# frozen_string_literal: true

require "prism"

module Phlex::Compiler
	def self.compile(component)
		path, line = Object.const_source_location(component.name)
		return unless File.exist?(path)
		source = File.read(path)
		tree = Prism.parse(source).value
		Compilation.new(component, path, line, source, tree).compile
	end
end
