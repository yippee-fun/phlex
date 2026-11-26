# frozen_string_literal: true

class CachingTest < Quickdraw::Test
	CacheStore = Phlex::FIFOCacheStore.new

	class CacheTest < Phlex::HTML
		def cache_store = CacheStore

		def initialize(execution_watcher)
			@execution_watcher = execution_watcher
		end

		def view_template
			cache do
				@execution_watcher.call
				"OK"
			end
		end
	end

	test "caching a block only executes once" do
		run_count = 0
		monitor = -> { run_count += 1 }
		CacheTest.new(monitor).call
		assert_equal run_count, 1
		CacheTest.new(monitor).call
		assert_equal run_count, 1
	end

	class RecoveringCacheTest < Phlex::HTML
		def initialize(cache_store, failure)
			@cache_store = cache_store
			@failure = failure
		end

		attr_reader :cache_store

		def view_template
			low_level_cache(:outer) do
				plain "before"
				catch(:abort) do
					low_level_cache(:inner) do
						plain "discarded"
						@failure.call
					end
				rescue RuntimeError
					plain "recovered"
				end
				plain "after"
			end
		end
	end

	test "an inner cache raising or throwing does not corrupt the outer cache" do
		[
			[-> { raise "failed" }, "beforerecoveredafter"],
			[-> { throw :abort }, "beforeafter"],
		].each do |failure, expected|
			cache_store = Phlex::FIFOCacheStore.new
			2.times do
				assert_equal RecoveringCacheTest.new(cache_store, failure).call, expected
			end
		end
	end

	class RecordingStore
		def initialize = @fetches = []

		attr_reader :fetches

		def fetch(key, **options)
			@fetches << [key, options]
			yield
		end
	end

	class KeyedCacheTest < Phlex::HTML
		def initialize(store) = @store = store

		def view_template
			cache(:a, expires_in: 1) { span }
			cache(:a) { em }
		end

		private def cache_store = @store
	end

	test "the cache key names the deploy, class, method and line, and options reach the store" do
		store = RecordingStore.new

		assert_equal KeyedCacheTest.new(store).call, "<span></span><em></em>"

		line = KeyedCacheTest.instance_method(:view_template).source_location[1]

		assert_equal store.fetches, [
			[[Phlex::DEPLOYED_AT, KeyedCacheTest.name, nil, "view_template", line + 1, [:a]], { expires_in: 1 }],
			[[Phlex::DEPLOYED_AT, KeyedCacheTest.name, nil, "view_template", line + 2, [:a]], {}],
		]
	end

	test "the cache key includes the class's identity when cache reloading is enabled" do
		store = RecordingStore.new

		component = Class.new(KeyedCacheTest) do
			private def enable_cache_reloading? = true

			private def app_version_key = "v2"
		end

		component.new(store).call

		assert_equal store.fetches.map { |key, _| key.first(3) }, [["v2", nil, component.object_id]] * 2
	end

	test "low_level_cache passes options to the store" do
		store = RecordingStore.new

		component = Class.new(Phlex::HTML) do
			define_method(:cache_store) { store }

			def view_template = low_level_cache([:key], expires_in: 2) { hr }
		end

		assert_equal component.call, "<hr>"
		assert_equal store.fetches, [[[:key], { expires_in: 2 }]]
	end
end
