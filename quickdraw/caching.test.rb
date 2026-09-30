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
end
