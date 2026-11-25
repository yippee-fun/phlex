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
		assert_equal store.fetch("a") { nil }.equal?(hit), defined?(::Ractor) ? true : false

		if defined?(::Ractor)
			assert ::Ractor.shareable?(hit)
			assert_raises(FrozenError) { hit[0] << "x" }
		end
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
end
