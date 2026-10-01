# frozen_string_literal: true

class SelectiveRenderingFromCacheTest < Quickdraw::Test
	class SymbolFragmentTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(page_id, cache_store:, piece_name: :piece)
			@page_id = page_id
			@cache_store = cache_store
			@piece_name = piece_name
		end

		def view_template
			low_level_cache(["page", @page_id]) do
				fragment(:outer) do
					div do
						low_level_cache("inner") do
							fragment(@piece_name) { span { "hello" } }
							fragment("other") { span { "world" } }
						end
					end
				end
			end
		end
	end

	test "rendering a symbol fragment on a cache miss and hit" do
		cache_store = Phlex::FIFOCacheStore.new
		2.times do
			assert_equal SymbolFragmentTest.new(1, cache_store:).call(fragments: [:piece]), "<span>hello</span>"
		end
	end

	test "symbol and string fragment names are equivalent on cache misses and hits" do
		[:piece, "piece"].each do |piece_name|
			[
				[[:piece], "<span>hello</span>"],
				[["piece"], "<span>hello</span>"],
				[[:piece, "piece"], "<span>hello</span>"],
				[[:piece, :other], "<span>hello</span><span>world</span>"],
				[[:outer, :piece, "other"], "<div><span>hello</span><span>world</span></div>"],
				[["outer", "piece", :other], "<div><span>hello</span><span>world</span></div>"],
			].each do |fragments, expected|
				cache_store = Phlex::FIFOCacheStore.new
				2.times do
					assert_equal SymbolFragmentTest.new(1, cache_store:, piece_name:).call(fragments:), expected
				end
			end
		end
	end

	test "symbol fragments imported from an inner cache preserve their names and nesting" do
		cache_store = Phlex::FIFOCacheStore.new
		SymbolFragmentTest.new(1, cache_store:).call

		2.times do
			output = SymbolFragmentTest.new(2, cache_store:).call(fragments: [:outer, :piece, "other"])
			assert_equal output, "<div><span>hello</span><span>world</span></div>"

			output = SymbolFragmentTest.new(2, cache_store:).call(fragments: [:piece])
			assert_equal output, "<span>hello</span>"
		end
	end

	test "compiled symbol fragments render with string selectors on cache misses and hits" do
		Phlex::Compiler.compile(SymbolFragmentTest)
		cache_store = Phlex::FIFOCacheStore.new
		2.times do
			output = SymbolFragmentTest.new(1, cache_store:).call(fragments: ["outer", "piece", :other])
			assert_equal output, "<div><span>hello</span><span>world</span></div>"
		end
	ensure
		Phlex::Compiler.decompile(SymbolFragmentTest)
	end

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

	test "fragments imported from an inner cache remain nested in outer fragments" do
		cache_store = Phlex::FIFOCacheStore.new
		CacheTest.new(1, cache_store:).call
		CacheTest.new(2, cache_store:).call

		[2, 3].each do |page_id|
			output = CacheTest.new(page_id, cache_store:).call(fragments: ["outer", "foo"])
			assert_equal output, '<div id="page"><section><ul><li>1</li><li>2</li><li>3</li></ul></section></div>'
		end
	end
end
