# frozen_string_literal: true

require "date"
require "erb"
require "set"
require "zeitwerk"

module Phlex
	Loader = Zeitwerk::Loader.for_gem.tap do |loader|
		loader.ignore("#{__dir__}/ruby_lsp")
		loader.ignore("#{__dir__}/phlex/compiler/scope.rb")

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

	# The main Ractor’s attribute cache. Other Ractors can’t read it, so each has its own.
	ATTRIBUTE_CACHE = FIFO.new(max_bytesize: 2 ** 20)
	@attribute_cache_max_bytesize = ATTRIBUTE_CACHE.max_bytesize

	UNBOUND_INSTANCE_METHOD_METHOD = Module.instance_method(:instance_method)

	# Filled by the compiler: compiled path => Phlex::Compiler::Generation.
	# Lives here so the runtime can consult it without loading the compiler,
	# and is replaced rather than mutated so any Ractor can read it.
	@compiled_source_maps = {}.freeze

	def self.__compiled_source_maps__ = @compiled_source_maps

	COMPILED_SOURCE_MAPS_MUTEX = Mutex.new

	def self.__add_compiled_source_map__(compiled_path, generation)
		COMPILED_SOURCE_MAPS_MUTEX.synchronize do
			@compiled_source_maps = @compiled_source_maps.merge(compiled_path => generation).freeze
		end
	end

	# The original line for a location that may be in compiled code.
	def self.__source_line__(location)
		if (generation = @compiled_source_maps[location.path])
			generation.lines[location.lineno] || location.lineno
		else
			location.lineno
		end
	end

	def self.__expand_attribute_cache__(file_path)
		return unless File.exist?(file_path)

		unless CACHED_FILES.include?(file_path)
			CACHED_FILES << file_path
			@attribute_cache_max_bytesize = Phlex::ATTRIBUTE_CACHE.expand(File.size(file_path))
		end
	end

	# __attribute_cache__ is called once per render, so the check is written out in each.
	if !defined?(::Ractor)
		def self.__main_ractor__? = true
		def self.__attribute_cache__ = ATTRIBUTE_CACHE
	elsif ::Ractor.respond_to?(:main?)
		def self.__main_ractor__? = ::Ractor.main?
		def self.__attribute_cache__ = ::Ractor.main? ? ATTRIBUTE_CACHE : __ractor_attribute_cache__
	else
		def self.__main_ractor__? = ::Ractor.current == ::Ractor.main
		def self.__attribute_cache__ = (::Ractor.current == ::Ractor.main) ? ATTRIBUTE_CACHE : __ractor_attribute_cache__
	end

	# A Ractor’s own cache is kept as large as the main one.
	def self.__ractor_attribute_cache__
		max_bytesize = @attribute_cache_max_bytesize
		cache = (::Ractor.current[:__phlex_attribute_cache__] ||= FIFO.new(max_bytesize:))
		cache.grow_to(max_bytesize) if cache.max_bytesize < max_bytesize
		cache
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
