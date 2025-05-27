# frozen_string_literal: true

require "erb"
require "set"
require "zeitwerk"

module Phlex
	Loader = Zeitwerk::Loader.for_gem.tap do |loader|
		loader.ignore("#{__dir__}/ruby_lsp")

		loader.inflector.inflect(
			"csv" => "CSV",
			"fifo" => "FIFO",
			"fifo_cache_store" => "FIFOCacheStore",
			"html" => "HTML",
			"sgml" => "SGML",
			"svg" => "SVG",
		)

		loader.collapse("#{__dir__}/phlex/errors")
		loader.setup
	end

	Escape = ERB::Escape

	DEPLOYED_AT = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
	CACHED_FILES = Set.new
	ATTRIBUTE_CACHE = FIFO.new

	def self.__expand_attribute_cache__(file_path)
		unless CACHED_FILES.include?(file_path)
			CACHED_FILES << file_path
			Phlex::ATTRIBUTE_CACHE.expand(File.size(file_path))
		end
	end

	# Generate an HTML string using Phlex’ HTML DSL
	def self.html(&block)
		HTML.call do |component|
			receiver = block.binding.receiver

			receiver.instance_variables.each do |ivar|
				next if component.instance_variable_defined?(ivar)

				value = receiver.instance_variable_get(ivar)
				component.instance_variable_set(ivar, value)
			end

			component.instance_exec(receiver, &block)
		end
	end

	# Generate an SVG string using Phlex’ SVG DSL
	def self.svg(&block)
		SVG.call do |component|
			receiver = block.binding.receiver

			receiver.instance_variables.each do |ivar|
				next if component.instance_variable_defined?(ivar)

				value = receiver.instance_variable_get(ivar)
				component.instance_variable_set(ivar, value)
			end

			component.instance_exec(receiver, &block)
		end
	end
end

def 💪
	Phlex
end
