# frozen_string_literal: true

# An extremely fast in-memory cache store that evicts keys on a first-in-first-out basis.
#
# Values are copied when they're stored, so changing what you cached doesn't
# change the cache. A value made only of Strings, Symbols, numbers, true,
# false, nil, Arrays and Hashes is kept as a deeply frozen copy, which every
# hit returns. Anything else may load itself in its own way, so it's kept
# serialised and each hit loads a new copy.
class Phlex::FIFOCacheStore
	# What the FIFO stores, whether it's still serialised, and the size of its serialised form.
	Entry = Data.define(:value, :serialized, :bytesize)

	def initialize(max_bytesize: 2 ** 20)
		@max_bytesize = max_bytesize
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
			entry.serialized ? Marshal.load(entry.value) : entry.value
		else
			result = yield
			dump = Marshal.dump(result)

			# The FIFO won't keep a value larger than the store.
			if dump.bytesize <= @max_bytesize
				fifo[key] = plain?(result) ? Entry.new(Marshal.load(dump, freeze: true), false, dump.bytesize) : Entry.new(dump, true, dump.bytesize)
			end

			result
		end
	end

	def clear
		@fifo.clear
	end

	private def plain?(value)
		case value
		when Symbol, Integer, Float, true, false, nil
			true
		when String
			String.equal?(value.class)
		when Array
			Array.equal?(value.class) && value.all? { |item| plain?(item) }
		when Hash
			Hash.equal?(value.class) && value.all? { |k, v| plain?(k) && plain?(v) }
		else
			false
		end
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
