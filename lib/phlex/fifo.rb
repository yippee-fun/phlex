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
		return if value.bytesize > @max_value_bytesize

		digest = key.hash

		@mutex.synchronize do
			# Check the key definitely doesn't exist now we have the lock
			return if @store[digest]

			@store[digest] = [key, value].freeze
			@bytesize += value.bytesize

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
