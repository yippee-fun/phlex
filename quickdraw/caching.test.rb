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
end
