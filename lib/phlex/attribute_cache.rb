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
class Phlex::AttributeCache < Phlex::FIFO
	Pairs = Data.define(:items)

	def fetch(attributes)
		digest = attributes.hash

		if (entry = @store[digest])
			snapshot, value = entry
			return matches?(snapshot, attributes) ? value : yield
		end

		value = yield
		return value if value.bytesize.zero? || value.bytesize > @max_value_bytesize

		snapshot = catch(:uncacheable) { snapshot(attributes) }
		store(digest, snapshot, value) unless :uncacheable == snapshot
		value
	end

	def [](attributes)
		snapshot, value = @store[attributes.hash]
		value if snapshot && matches?(snapshot, attributes)
	end

	def []=(attributes, value)
		snapshot = catch(:uncacheable) { snapshot(attributes) }
		store(attributes.hash, snapshot, value) unless :uncacheable == snapshot
	end

	private def snapshot(value)
		case value
		when Symbol, Integer, true, false, nil
			value
		when String
			throw :uncacheable, :uncacheable unless String.equal?(value.class) && !(Phlex::SGML::SafeObject === value)
			-value
		when Phlex::SGML::SafeValue
			throw :uncacheable, :uncacheable unless Phlex::SGML::SafeValue.equal?(value.class) && String.equal?(value.to_s.class)
			Phlex::SGML::SafeValue.new(-value.to_s)
		when Hash
			throw :uncacheable, :uncacheable unless Hash.equal?(value.class)
			Pairs.new(value.flat_map { |k, v| [snapshot_key(k), snapshot(v)] }.freeze)
		when Array
			throw :uncacheable, :uncacheable unless Array.equal?(value.class)
			value.map { |item| snapshot(item) }.freeze
		else
			throw :uncacheable, :uncacheable
		end
	end

	# A pair with a nil or false value is skipped when serialising, so its key
	# can be anything, even a cyclic Array.
	private def snapshot_key(key)
		case key
		when Symbol, String then snapshot(key)
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
