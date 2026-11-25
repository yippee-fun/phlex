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

	class InvalidUTF8CacheTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(cache_store:)
			@cache_store = cache_store
		end

		def view_template
			cache("page") do
				fragment("before") { span { "a" } }
				raw(safe("\xFF"))
				fragment("after") { span { "b" } }
			end
		end
	end

	test "invalid UTF-8 content renders identically on cache misses and hits" do
		cache_store = Phlex::FIFOCacheStore.new
		expected = "<span>a</span>\xFF<span>b</span>"

		2.times do
			output = InvalidUTF8CacheTest.new(cache_store:).call
			assert_equal output.b, expected.b
			assert_equal output.encoding, Encoding::UTF_8

			assert_equal InvalidUTF8CacheTest.new(cache_store:).call(fragments: ["after"]), "<span>b</span>"
		end
	end

	class HaltTest < Phlex::HTML
		attr_reader :cache_store, :events

		def initialize(cache_store:)
			@cache_store = cache_store
			@events = []
		end

		def view_template
			cache do
				fragment("target") { h1 { "Target" } }
			end

			@events << :after_cache
			fragment("other") { h1 { "Other" } }
		end

		private def after_template
			@events << :after_template
		end
	end

	test "halts after selecting the last fragment from a cache" do
		cache_store = Phlex::FIFOCacheStore.new

		2.times do
			component = HaltTest.new(cache_store:)
			assert_equal component.call(fragments: ["target"]), "<h1>Target</h1>"
			assert_equal component.events, []
		end
	end

	test "keeps rendering after a cache when fragments remain" do
		cache_store = Phlex::FIFOCacheStore.new

		2.times do
			component = HaltTest.new(cache_store:)
			assert_equal component.call(fragments: ["target", "other"]), "<h1>Target</h1><h1>Other</h1>"
			assert_equal component.events, [:after_cache]
		end
	end

	test "doesn't halt after a cache when no fragments were selected from it" do
		cache_store = Phlex::FIFOCacheStore.new

		2.times do
			component = HaltTest.new(cache_store:)
			assert_equal component.call(fragments: []), ""
			assert_equal component.events, [:after_cache, :after_template]
		end
	end

	class NestedDuplicateTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(key, cache_store:)
			@key = key
			@cache_store = cache_store
		end

		def view_template
			if @key
				cache(@key) { content { cache { inner } } }
			else
				content { inner }
			end
		end

		def inner
			fragment("target") { plain "B" }
		end

		def content
			fragment("target") do
				plain "é"
				yield
				plain "C"
			end
		end
	end

	test "a fragment nested in a fragment of the same name ends the selection, cached or not" do
		cache_store = Phlex::FIFOCacheStore.new

		assert_equal NestedDuplicateTest.new(nil, cache_store:).call(fragments: ["target"]), "éB"

		# Both caches cold, then only the inner cache warm, then both warm.
		[1, 2, 2].each do |key|
			assert_equal NestedDuplicateTest.new(key, cache_store:).call(fragments: ["target"]), "éB"
		end
	end

	class ImportedFragmentsTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(key, cache_store:, same_name:)
			@key = key
			@cache_store = cache_store
			@same_name = same_name
		end

		def view_template
			if @key
				cache(@key, @same_name) { parent { cache(@same_name) { inner } } }
			else
				parent { inner }
			end
		end

		def parent
			fragment("parent") do
				plain "A"
				yield
				plain "C"
			end
		end

		def inner
			if @same_name
				fragment("parent") { child }
			else
				child
			end
		end

		def child
			fragment("child") { plain "B" }
		end
	end

	test "a parent selected with a child from an inner cache renders the child once" do
		cache_store = Phlex::FIFOCacheStore.new

		# Uncached, then both caches cold, then only the inner cache warm, then both warm.
		[nil, 1, 2, 2].each do |key|
			assert_equal ImportedFragmentsTest.new(key, cache_store:, same_name: false).call(fragments: ["parent", "child"]), "ABC"
			assert_equal ImportedFragmentsTest.new(key, cache_store:, same_name: true).call(fragments: ["parent", "child"]), "AB"
		end
	end

	class DuplicateTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(cache_store:, cached:)
			@cache_store = cache_store
			@cached = cached
		end

		def view_template
			if @cached
				cache { cache { content } }
			else
				content
			end
		end

		def content
			fragment("target") { h1 { "First" } }
			fragment("wrapper") do
				fragment("target") { h1 { "Second" } }
			end
		end
	end

	test "duplicate fragment names select the first fragment, cached or not" do
		cache_store = Phlex::FIFOCacheStore.new

		assert_equal DuplicateTest.new(cache_store:, cached: false).call(fragments: ["target"]), "<h1>First</h1>"

		2.times do
			assert_equal DuplicateTest.new(cache_store:, cached: true).call(fragments: ["target"]), "<h1>First</h1>"
		end
	end

	test "a duplicate fragment name doesn't change the fragment that contains it" do
		cache_store = Phlex::FIFOCacheStore.new

		assert_equal DuplicateTest.new(cache_store:, cached: false).call(fragments: ["wrapper"]), "<h1>Second</h1>"

		2.times do
			assert_equal DuplicateTest.new(cache_store:, cached: true).call(fragments: ["wrapper"]), "<h1>Second</h1>"
		end
	end

	class OverlappingTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(key, cache_store:, inner_cache:)
			@key = key
			@cache_store = cache_store
			@inner_cache = inner_cache
		end

		def view_template
			if @key
				cache(@key, @inner_cache) { content }
			else
				content
			end
		end

		def content
			fragment("target") do
				fragment("other") do
					plain "A"
					if @key && @inner_cache
						cache { inner }
					else
						inner
					end
					plain "C"
				end
			end
		end

		def inner
			fragment("target") { plain "B" }
		end
	end

	test "a fragment that outlives a same-name fragment closing its parent isn't nested in it" do
		[false, true].each do |inner_cache|
			cache_store = Phlex::FIFOCacheStore.new

			# Uncached, then cold, then warm (with an inner cache: only the inner cache warm, then both warm).
			[nil, 1, 2, 2].each do |key|
				component = OverlappingTest.new(key, cache_store:, inner_cache:)
				assert_equal component.call(fragments: ["target", "other"]), "ABC"
			end
		end
	end

	class InnerCacheEndsSelectionTest < Phlex::HTML
		attr_reader :cache_store

		def initialize(cached, cache_store:)
			@cached = cached
			@cache_store = cache_store
		end

		def view_template
			fragment("target") do
				plain "A"
				@cached ? cache { inner } : inner
				plain "C"
			end

			fragment("other") { plain "D" }
		end

		def inner
			fragment("target") { plain "B" }
			plain "E"
		end
	end

	test "a same-name fragment in an inner cache ends an open selected fragment" do
		cache_store = Phlex::FIFOCacheStore.new

		# Uncached, then cold, then warm.
		[false, true, true].each do |cached|
			assert_equal InnerCacheEndsSelectionTest.new(cached, cache_store:).call(fragments: ["target"]), "AB"
			assert_equal InnerCacheEndsSelectionTest.new(cached, cache_store:).call(fragments: ["target", "other"]), "ABD"
		end
	end
end
