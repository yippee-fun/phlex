# frozen_string_literal: true

# An extremely fast in-memory cache store that evicts keys on a first-in-first-out basis.
#
# Values are copied when they're stored, so changing what you cached doesn't
# change the cache. A hit returns that deeply frozen copy, rather than a new
# copy each time, where Ractors are available to freeze it.
class Phlex::FIFOCacheStore
	# What the FIFO stores, and the size of its serialised form.
	Entry = Data.define(:value, :bytesize)

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

		if (entry = fifo[key])
			load_value(entry.value)
		else
			result = yield
			dump = Marshal.dump(result)
			fifo[key] = Entry.new(store_value(dump), dump.bytesize)
			result
		end
	end

	def clear
		@fifo.clear
	end

	if defined?(::Ractor)
		private def store_value(dump) = ::Ractor.make_shareable(Marshal.load(dump))
		private def load_value(value) = value
	else
		# Without Ractors there's no deep freeze, so each hit loads its own copy.
		private def store_value(dump) = dump
		private def load_value(value) = Marshal.load(value)
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
