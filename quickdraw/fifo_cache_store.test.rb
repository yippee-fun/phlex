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
end
