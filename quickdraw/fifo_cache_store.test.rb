# frozen_string_literal: true

class FIFOCacheStoreTest < Quickdraw::Test
	test "fetch caches the yield" do
		store = Phlex::FIFOCacheStore.new
		count = 0

		first_read = store.fetch("a") do
			count += 1
			"A"
		end

		assert_equal first_read, "A"
		assert_equal count, 1

		second_read = store.fetch("a") do
			failure! { "This block should not have been called." }
			"B"
		end

		assert_equal second_read, "A"
		assert_equal count, 1
	end

	test "nested caches do not lead to contention" do
		store = Phlex::FIFOCacheStore.new

		result = store.fetch("a") do
			[
				"A",
				store.fetch("b") { "B" },
			].join(", ")
		end

		assert_equal result, "A, B"
	end

	test "fetch accepts and ignores options" do
		store = Phlex::FIFOCacheStore.new

		assert_equal store.fetch("a", expires_in: 10) { "A" }, "A"
		assert_equal store.fetch("a", expires_in: 10) { "B" }, "A"
	end

	test "components can pass cache options" do
		component = Class.new(Phlex::HTML) do
			def cache_store = @cache_store ||= Phlex::FIFOCacheStore.new
			def view_template = cache(1, expires_in: 10) { div { "x" } }
		end

		assert_equal component.new.call, "<div>x</div>"
	end

	test "fetch preserves invalid UTF-8 content" do
		store = Phlex::FIFOCacheStore.new
		value = "<p>\xFF</p>"

		2.times do
			result = store.fetch("a") { value }
			assert_equal result.b, value.b
			assert_equal result.encoding, Encoding::UTF_8
		end
	end

	test "fetch preserves binary content" do
		store = Phlex::FIFOCacheStore.new
		value = "\x00\xFF\xFE".b

		2.times do
			result = store.fetch("a") { value }
			assert_equal result, value
			assert_equal result.encoding, Encoding::BINARY
		end
	end

	test "a hit returns a value equal to the miss" do
		store = Phlex::FIFOCacheStore.new
		value = ["<div><span>x</span></div>", { "outer" => [0, 26, ["inner"]], "inner" => [5, 14, []] }]

		miss = store.fetch("a") { value }
		hit = store.fetch("a") { failure! { "This block should not have been called." } }

		assert_equal miss, value
		assert_equal hit, miss
	end

	test "a hit is a frozen copy that changing the cached value doesn't change" do
		store = Phlex::FIFOCacheStore.new
		value = [+"<div>", { "a" => [0, 5, []] }]

		store.fetch("a") { value }
		value[0] << "changed"
		value[1]["a"][2] << "b"

		hit = store.fetch("a") { failure! { "This block should not have been called." } }

		assert_equal hit, ["<div>", { "a" => [0, 5, []] }]
		assert store.fetch("a") { nil }.equal?(hit)
		assert_raises(FrozenError) { hit[0] << "x" }
		assert_raises(FrozenError) { hit[1]["a"][2] << "x" }
		assert ::Ractor.shareable?(hit) if defined?(::Ractor)
	end

	test "other values are loaded anew on each hit, without freezing what their loader returns" do
		lock = Object.const_set(:FIFOCacheStoreTestLock, Class.new do
			def initialize = @mutex = Mutex.new
			def marshal_dump = nil
			def marshal_load(_) = @mutex = Mutex.new
			def locked? = @mutex.locked?
		end)

		registry = {}
		registered_class = Object.const_set(:FIFOCacheStoreTestRegistered, Class.new do
			attr_reader :name

			define_method(:initialize) { |name| @name = name }
			define_method(:_dump) { |_| @name }
			define_singleton_method(:_load) { |name| registry[name] ||= new(name) }
		end)

		store = Phlex::FIFOCacheStore.new

		store.fetch("lock") { [lock.new] }
		first = store.fetch("lock") { nil }
		second = store.fetch("lock") { nil }

		refute first.frozen?
		refute first.equal?(second)
		refute first[0].locked?

		registered = registry["x"] = registered_class.new(+"x")
		store.fetch("registered") { [registered] }

		assert store.fetch("registered") { nil }[0].equal?(registered)
		refute registered.frozen?
		refute registered.name.frozen?
	ensure
		Object.__send__(:remove_const, :FIFOCacheStoreTestLock) if Object.const_defined?(:FIFOCacheStoreTestLock, false)
		Object.__send__(:remove_const, :FIFOCacheStoreTestRegistered) if Object.const_defined?(:FIFOCacheStoreTestRegistered, false)
	end

	test "a value is classified before a dump hook can change it" do
		registry = {}
		hooked = Object.const_set(:FIFOCacheStoreTestHooked, Class.new do
			attr_accessor :owner

			define_method(:_dump) { |_| owner.default = nil; "hooked" }
			define_singleton_method(:_load) { |name| registry[name] ||= new }
		end)

		value = {}
		value.default = hooked.new.tap { |it| it.owner = value }
		store = Phlex::FIFOCacheStore.new
		store.fetch("hooked") { value }
		hit = store.fetch("hooked") { nil }

		assert hit.default.equal?(registry["hooked"])
		refute hit.frozen?
		refute registry["hooked"].frozen?
	ensure
		Object.__send__(:remove_const, :FIFOCacheStoreTestHooked) if Object.const_defined?(:FIFOCacheStoreTestHooked, false)
	end

	test "core objects with singleton methods are loaded on each hit" do
		registered = +"registered"
		String.define_singleton_method(:_load) { |_| registered }

		hooked = +"hooked"
		hooked.define_singleton_method(:_dump) { |_| "hooked" }
		store = Phlex::FIFOCacheStore.new
		store.fetch("singleton") { [hooked] }

		assert store.fetch("singleton") { nil }[0].equal?(registered)
		refute registered.frozen?
	ensure
		String.singleton_class.remove_method(:_load) if String.singleton_class.method_defined?(:_load, false)
	end

	test "cyclic values and core objects with instance variables are loaded on each hit" do
		store = Phlex::FIFOCacheStore.new

		cyclic = [1]
		cyclic << cyclic
		store.fetch("cyclic") { cyclic }
		hit = store.fetch("cyclic") { nil }

		assert hit[1].equal?(hit)
		refute hit.frozen?

		tagged = +"tagged"
		tagged.instance_variable_set(:@tag, [+"mutable"])
		store.fetch("tagged") { [tagged] }
		hit = store.fetch("tagged") { nil }

		assert_equal hit[0].instance_variable_get(:@tag), ["mutable"]
		refute hit[0].instance_variable_get(:@tag).frozen?
	end

	test "frozen hits keep shared and distinct strings as they were" do
		store = Phlex::FIFOCacheStore.new

		shared = +"x"
		store.fetch("strings") { [shared, shared, +"y", +"y"] }
		hit = store.fetch("strings") { nil }

		assert hit.frozen?
		assert hit[0].equal?(hit[1])
		refute hit[2].equal?(hit[3])
	end

	test "identity hashes keep their distinct keys on each hit" do
		store = Phlex::FIFOCacheStore.new

		identity = {}.compare_by_identity
		identity[+"a"] = 1
		identity[+"a"] = 2
		store.fetch("identity") { identity }
		hit = store.fetch("identity") { nil }

		assert_equal hit.size, 2
		assert hit.compare_by_identity?
	end

	test "deeply nested values are classified without overflowing the stack" do
		# Deep enough to overflow a recursive walk, and checked directly because
		# Marshal itself recurses on some Rubies.
		deep = 100_000.times.reduce([]) { |inner, _| [inner] }

		assert Phlex::FIFOCacheStore.new.__send__(:plain?, deep)
	end

	test "values larger than the store aren't cached" do
		store = Phlex::FIFOCacheStore.new(max_bytesize: 10)

		assert_equal store.fetch("a") { "a" * 20 }, "a" * 20
		assert_equal store.fetch("a") { "missed" }, "missed"
	end

	test "values that can't be serialised aren't cached" do
		store = Phlex::FIFOCacheStore.new

		assert_raises(TypeError) { store.fetch("a") { proc {} } }
		assert_equal store.fetch("a") { "A" }, "A"
	end

	test "evicts by the size of the serialised value" do
		store = Phlex::FIFOCacheStore.new(max_bytesize: 40)

		store.fetch("a") { "a" * 20 }
		store.fetch("b") { "b" * 20 }

		assert_equal store.fetch("a") { "missed" }, "missed"
	end

	private def frozen_hit?(value)
		store = Phlex::FIFOCacheStore.new
		store.fetch("key") { value }
		hit = store.fetch("key") { failure! { "This block should not have been called." } }

		assert_equal hit, value
		hit.frozen? && store.fetch("key") { nil }.equal?(hit)
	end

	test "a value made of plain objects, true and false included, is a frozen hit" do
		assert frozen_hit?([true, false, nil, :a, 1, 1.5, "a", { "a" => [true] }])
	end

	test "a value holding a subclass, a hash with a default, or a shared container is loaded on each hit" do
		stub_const("FIFOCacheStoreTestArray", Class.new(Array))
		stub_const("FIFOCacheStoreTestHash", Class.new(Hash))
		stub_const("FIFOCacheStoreTestString", Class.new(String))

		shared_hash = { "a" => 1 }
		shared_array = [1]

		refute frozen_hit?([FIFOCacheStoreTestArray.new([1])])
		refute frozen_hit?([FIFOCacheStoreTestHash[1, 2]])
		refute frozen_hit?({ "a" => FIFOCacheStoreTestString.new("b") })
		refute frozen_hit?([FIFOCacheStoreTestString.new("b")])
		refute frozen_hit?([Hash.new(0).merge!("a" => 1)])
		refute frozen_hit?([{}.compare_by_identity])
		refute frozen_hit?([shared_hash, shared_hash])
		refute frozen_hit?([shared_array, shared_array])
	end

	test "keys made of objects with cache keys hit for another object with the same cache key" do
		record = Class.new do
			define_method(:initialize) { |key| @key = key }
			define_method(:cache_key) { @key }
		end

		versioned = Class.new(record) do
			define_method(:cache_key_with_version) { "#{@key}-v1" }
		end

		store = Phlex::FIFOCacheStore.new

		store.fetch([record.new("a"), { b: record.new("b") }]) { "value" }
		store.fetch(versioned.new("c")) { "versioned" }
		store.fetch(false) { "false" }

		assert_equal store.fetch([record.new("a"), { b: record.new("b") }]) { "miss" }, "value"
		assert_equal store.fetch(versioned.new("c")) { "miss" }, "versioned"
		assert_equal store.fetch("c-v1") { "miss" }, "versioned"
		assert_equal store.fetch(false) { "miss" }, "false"
	end
end
