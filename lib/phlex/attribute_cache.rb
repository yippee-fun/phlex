# frozen_string_literal: true

# @api private
#
# Caches serialised attributes. Hash#eql? ignores order, a String's class and
# whether it's a safe object, any of which can change the output, so a hit
# must match the frozen snapshot taken when it was cached, in order and class
# for class. The snapshot interns its Strings, so a frozen literal matches by
# identity, and a safe object can't, since it can't be frozen before it's
# extended. Only plain Hashes, Arrays, Strings, SafeValues, Symbols, Integers,
# true, false and nil are cached; anything else is serialised every time.
#
# The snapshot is kept with the output, so it counts against the budget too:
# each value it holds costs SLOT_BYTESIZE, plus a String's bytes. Attributes
# whose snapshot and output together cost more than one value may aren't
# cached, so a large input that renders to little, such as an Array of nils,
# can't hold memory the budget doesn't see.
class Phlex::AttributeCache < Phlex::FIFO
	Pairs = Data.define(:items)
	SLOT_BYTESIZE = 8

	def fetch(attributes)
		digest = attributes.hash

		if (entry = @store[digest])
			snapshot, value = entry
			return matches?(snapshot, attributes) ? value : yield
		end

		value = yield
		return value if value.bytesize.zero? || value.bytesize > @max_value_bytesize

		remaining = [@max_value_bytesize - value.bytesize]
		snapshot = catch(:uncacheable) { snapshot(attributes, remaining) }
		store(digest, snapshot, value, @max_value_bytesize - remaining[0]) unless :uncacheable == snapshot
		value
	end

	def append(buffer, attributes, &)
		buffer << fetch(attributes, &)
	end

	def [](attributes)
		snapshot, value = @store[attributes.hash]
		value if snapshot && matches?(snapshot, attributes)
	end

	def []=(attributes, value)
		return if value.bytesize > @max_value_bytesize

		remaining = [@max_value_bytesize - value.bytesize]
		snapshot = catch(:uncacheable) { snapshot(attributes, remaining) }
		store(attributes.hash, snapshot, value, @max_value_bytesize - remaining[0]) unless :uncacheable == snapshot
	end

	# `remaining` holds what's left of the entry's budget, and running out of it
	# stops the walk, so a large input is given up on early.
	private def snapshot(value, remaining)
		throw :uncacheable, :uncacheable if (remaining[0] -= SLOT_BYTESIZE) < 0

		case value
		when Symbol, Integer, true, false, nil
			value
		when String
			throw :uncacheable, :uncacheable unless String.equal?(value.class) && !(Phlex::SGML::SafeObject === value)
			throw :uncacheable, :uncacheable if (remaining[0] -= value.bytesize) < 0
			-value
		when Phlex::SGML::SafeValue
			throw :uncacheable, :uncacheable unless Phlex::SGML::SafeValue.equal?(value.class) && String.equal?(value.to_s.class)
			throw :uncacheable, :uncacheable if (remaining[0] -= value.to_s.bytesize) < 0
			Phlex::SGML::SafeValue.new(-value.to_s)
		when Hash
			throw :uncacheable, :uncacheable unless Hash.equal?(value.class)
			Pairs.new(value.flat_map { |k, v| [snapshot_key(k, remaining), snapshot(v, remaining)] }.freeze)
		when Array
			throw :uncacheable, :uncacheable unless Array.equal?(value.class)
			value.map { |item| snapshot(item, remaining) }.freeze
		else
			throw :uncacheable, :uncacheable
		end
	end

	# A pair with a nil or false value is skipped when serialising, so its key
	# can be anything, even a cyclic Array.
	private def snapshot_key(key, remaining)
		case key
		when Symbol, String then snapshot(key, remaining)
		else throw :uncacheable, :uncacheable
		end
	end

	private def matches?(snapshot, value)
		case snapshot
		when Pairs
			items = snapshot.items
			return false unless Hash.equal?(value.class) && value.size * 2 == items.size

			i = 0
			value.each do |k, v|
				key = items[i]
				item = items[i + 1]
				return false unless key.equal?(k) || matches?(key, k)
				return false unless item.equal?(v) || matches?(item, v)
				i += 2
			end

			true
		when Array
			return false unless Array.equal?(value.class) && value.size == snapshot.size

			i = 0
			while i < snapshot.size
				item = snapshot[i]
				return false unless item.equal?(value[i]) || matches?(item, value[i])
				i += 1
			end

			true
		when String
			String.equal?(value.class) && snapshot.eql?(value) && snapshot.encoding == value.encoding && !(Phlex::SGML::SafeObject === value)
		when Phlex::SGML::SafeValue
			Phlex::SGML::SafeValue.equal?(value.class) && String.equal?(value.to_s.class) && snapshot.to_s.eql?(value.to_s) && snapshot.to_s.encoding == value.to_s.encoding
		else
			snapshot.eql?(value)
		end
	end
end
