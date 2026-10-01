# frozen_string_literal: true

require "json"

# An extremely fast in-memory cache store that evicts keys on a first-in-first-out basis.
class Phlex::FIFOCacheStore
	def initialize(max_bytesize: 2 ** 20)
		@fifo = Phlex::FIFO.new(
			max_bytesize:,
			max_value_bytesize: max_bytesize
		)
	end

	# Options such as `expires_in:` are accepted for compatibility with `Rails.cache` but ignored.
	def fetch(key, **)
		fifo = @fifo
		key = map_key(key)

		if (result = fifo[key])
			JSON.parse(result)
		else
			result = yield

			fifo[key] = JSON.generate(result)

			result
		end
	end

	def clear
		@fifo.clear
	end

	private def map_key(value)
		case value
		when Array
			value.map { |it| map_key(it) }
		when Hash
			value.to_h { |k, v| [map_key(k), map_key(v)].freeze }
		when String, Symbol, Integer, Float, Time, true, false, nil
			value
		else
			if value.respond_to?(:cache_key_with_version)
				map_key(value.cache_key_with_version)
			elsif value.respond_to?(:cache_key)
				map_key(value.cache_key)
			else
				raise ArgumentError.new("Invalid cache key: #{value.class}")
			end
		end
	end
end
