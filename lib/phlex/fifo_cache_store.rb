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
			# Classified before dumping, since a custom dump hook could change the value.
			plain = plain?(result)
			dump = Marshal.dump(result)

			# The FIFO won't keep a value larger than the store. A plain value is
			# frozen as it loads, not with `freeze: true`, which would deduplicate
			# equal Strings. The proc is made here because other Ractors can't share one.
			if dump.bytesize <= @max_bytesize
				fifo[key] = plain ? Entry.new(Marshal.load(dump, proc(&:freeze)), false, dump.bytesize) : Entry.new(dump, true, dump.bytesize)
			end

			result
		end
	end

	def clear
		@fifo.clear
	end

	# Shared or cyclic containers, identity hashes and core objects carrying
	# instance variables aren't plain, so the walk is linear and nothing but the
	# copy is frozen. It uses its own stack so deep values can't overflow Ruby's.
	private def plain?(value)
		seen = {}.compare_by_identity
		stack = [value]

		while (stack.length > 0)
			case (item = stack.pop)
			when Symbol, Integer, Float, true, false, nil
				next
			when String
				return false unless String.equal?(item.class) && item.instance_variables.empty?
			when Array
				return false unless Array.equal?(item.class) && item.instance_variables.empty? && !seen.key?(item)
				seen[item] = true
				stack.concat(item)
			when Hash
				return false unless Hash.equal?(item.class) && item.instance_variables.empty? && item.default.nil? && !item.compare_by_identity? && !seen.key?(item)
				seen[item] = true
				item.each { |k, v| stack << k << v }
			else
				return false
			end
		end

		true
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
