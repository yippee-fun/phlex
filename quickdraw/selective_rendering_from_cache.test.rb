# frozen_string_literal: true

class SelectiveRenderingFromCacheTest < Quickdraw::Test
	class CacheTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(page_id, cache_store:)
			@page_id = page_id
			@cache_store = cache_store
		end

		def view_template
			cache(@page_id) do
				h1 { "Page #{@page_id}" }
				fragment("outer") do
					div(id: "page") do
						cache do
							section do
								fragment("list") do
									ul do
										fragment("foo") { li { 1 } }
										li { 2 }
										li { 3 }
									end
								end
							end
						end
					end
				end
			end
		end
	end

	test "rendering a component with caches and fragments" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call
		assert_equal output, "<h1>Page 1</h1><div id=\"page\"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>"

		output = CacheTest.new(1, cache_store:).call
		assert_equal output, "<h1>Page 1</h1><div id=\"page\"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>"
	end

	test "rendering a component with caches and fragments" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call
		assert_equal output, "<h1>Page 1</h1><div id=\"page\"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>"

		output = CacheTest.new(2, cache_store:).call
		assert_equal output, "<h1>Page 2</h1><div id=\"page\"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>"
	end

	test "rendering a specific fragment from within a cache" do
		cache_store = Phlex::FIFOCacheStore.new
		2.times do
			output = CacheTest.new(2, cache_store:).call(fragments: ["list"])
			assert_equal output, "<ul><li>1</li><li>2</li><li>3</li></ul>"
		end
	end

	test "rendering a nested fragment from within a cache" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call(fragments: ["foo"])
		assert_equal output, "<li>1</li>"
	end

	test "rendering multiple fragments from within a cache" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call(fragments: ["list", "foo"])
		assert_equal output, "<ul><li>1</li><li>2</li><li>3</li></ul>"
	end

	test "rendering multiple fragments out of order from within a cache" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call(fragments: ["foo", "list"])
		assert_equal output, "<ul><li>1</li><li>2</li><li>3</li></ul>"
	end

	test "cache contains full value if initially rendered as a fragment" do
		cache_store = Phlex::FIFOCacheStore.new
		output = CacheTest.new(1, cache_store:).call(fragments: ["foo"])
		assert_equal output, "<li>1</li>"

		output = CacheTest.new(1, cache_store:).call
		assert_equal output, "<h1>Page 1</h1><div id=\"page\"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>"
	end

	test "fetching a nested fragment from a cached value" do
		cache_store = Phlex::FIFOCacheStore.new
		CacheTest.new(1, cache_store:).call # Cache the outer cache for key = 1, and the inner cache for all other keys
		output = CacheTest.new(2, cache_store:).call(fragments: ["foo"])
		assert_equal output, "<li>1</li>"
	end
end
