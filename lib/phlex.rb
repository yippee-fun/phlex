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
	ATTRIBUTE_CACHE_MAX_BYTESIZE = 2 ** 20

	# The main Ractor’s attribute cache. A FIFO is not shareable, so a non-main
	# Ractor can’t read this constant — it gets its own through Phlex.attribute_cache.
	ATTRIBUTE_CACHE = FIFO.new(max_bytesize: ATTRIBUTE_CACHE_MAX_BYTESIZE)

	# Bytes every attribute cache has been expanded by so far (see
	# __expand_attribute_cache__), so a Ractor-local cache starts the same size.
	@attribute_cache_expansion = 0

	UNBOUND_INSTANCE_METHOD_METHOD = Module.instance_method(:instance_method)

	# Filled by the compiler: compiled path => Phlex::Compiler::Generation.
	# Lives here so the runtime can consult it without loading the compiler.
	COMPILED_SOURCE_MAPS = {}

	# A frozen, Ractor-shareable copy of COMPILED_SOURCE_MAPS, republished by the
	# compiler after each write, so renders on any Ractor can read it.
	@compiled_source_maps = {}.freeze

	def self.__compiled_source_maps__ = @compiled_source_maps

	# Only the compiler calls this, on the main Ractor and under its lock.
	def self.__publish_compiled_source_map__(path, generation)
		@compiled_source_maps = @compiled_source_maps.merge(path => generation).freeze
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
			bytes = File.size(file_path)
			@attribute_cache_expansion += bytes
			Phlex::ATTRIBUTE_CACHE.expand(bytes)
		end
	end

	# The attribute cache for the current Ractor: ATTRIBUTE_CACHE on the main
	# Ractor, a Ractor-local FIFO anywhere else (sized like the main one,
	# including the expansion for every view_template seen so far). Resolved
	# once per render into Phlex::SGML::State, never per element.
	#
	# Before Ruby 4.0 a non-main Ractor can’t autoload, so on Ruby 3.2 and 3.3
	# call `Phlex::Loader.eager_load` before spawning one. Rubies without Ractors
	# (TruffleRuby, JRuby) always use ATTRIBUTE_CACHE.
	if !defined?(::Ractor)
		def self.attribute_cache
			ATTRIBUTE_CACHE
		end
	elsif ::Ractor.respond_to?(:store_if_absent) # Ruby 3.4+
		def self.attribute_cache
			if Ractor.main?
				ATTRIBUTE_CACHE
			else
				__sized_attribute_cache__(Ractor.store_if_absent(:__phlex_attribute_cache__) { __new_attribute_cache__ })
			end
		end
	else
		def self.attribute_cache
			ractor = Ractor.current

			if ractor == Ractor.main
				ATTRIBUTE_CACHE
			else
				__sized_attribute_cache__(ractor[:__phlex_attribute_cache__] ||= __new_attribute_cache__)
			end
		end
	end

	def self.__new_attribute_cache__
		FIFO.new(max_bytesize: ATTRIBUTE_CACHE_MAX_BYTESIZE + @attribute_cache_expansion)
	end

	# __expand_attribute_cache__ only reaches the main cache, so a Ractor-local
	# cache catches up with templates defined since it was created when it's
	# next fetched (once per render).
	def self.__sized_attribute_cache__(cache)
		target = ATTRIBUTE_CACHE_MAX_BYTESIZE + @attribute_cache_expansion
		cache.grow_to(target) if cache.max_bytesize < target
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
