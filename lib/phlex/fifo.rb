# frozen_string_literal: true

# @api private
class Phlex::FIFO
	# The byte limits account for cached values, excluding keys and object overhead.
	def initialize(max_bytesize: 2_000, max_value_bytesize: 2_000)
		@store = {}
		@max_bytesize = max_bytesize
		@max_value_bytesize = max_value_bytesize
		@bytesize = 0
		@mutex = Monitor.new
	end

	attr_reader :bytesize, :max_bytesize

	def expand(bytes)
		@mutex.synchronize do
			@max_bytesize += bytes
		end
	end

	def [](key)
		k, v = @store[key.hash]
		v if k.eql?(key)
	end

	# Returns the cached value for `key`, or yields to generate it and caches the
	# result. Unlike `fifo[key] ||= value`, the key is only hashed once.
	def fetch(key)
		digest = key.hash
		if (entry = @store[digest])
			k, v = entry
			return v if k.eql?(key)
		end

		value = yield
		store(digest, key, value)
		value
	end

	def []=(key, value)
		store(key.hash, key, value)
	end

	private def store(digest, key, value)
		bytesize = value.bytesize
		# Empty values would retain keys without consuming the eviction budget.
		return if bytesize.zero? || bytesize > @max_value_bytesize

		@mutex.synchronize do
			# Check the key definitely doesn't exist now we have the lock
			return if @store[digest]

			@store[digest] = [key, value].freeze
			@bytesize += bytesize

			while @bytesize > @max_bytesize
				_k, v = @store.shift
				@bytesize -= v[1].bytesize
			end
		end
	end

	def size
		@store.size
	end

	def clear
		@mutex.synchronize do
			@store.clear
			@bytesize = 0
		end
	end
end
