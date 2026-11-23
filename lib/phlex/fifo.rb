# frozen_string_literal: true

# @api private
class Phlex::FIFO
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

	def []=(key, value)
		store(key.hash, key, value)
	end

	# `bytesize` is what the entry counts against the budget, which is the
	# value's unless the caller also counts its key.
	private def store(digest, key, value, bytesize = value.bytesize)
		return if bytesize > @max_value_bytesize

		@mutex.synchronize do
			# Check the key definitely doesn't exist now we have the lock
			return if @store[digest]

			@store[digest] = [key, value, bytesize].freeze
			@bytesize += bytesize

			while @bytesize > @max_bytesize
				_k, entry = @store.shift
				@bytesize -= entry[2]
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
