# frozen_string_literal: true

module EquivalenceCases
	module CaptureAndCache
		class CaptureAndCache < Phlex::HTML
			CACHE_STORE = Phlex::FIFOCacheStore.new

			def view_template
				cache("k") { div { "cached" } }
				cache("k") { div { "cached" } }
				s = capture { div { "captured" } }
				pre { s }
				vanish { div { "vanished" } }
				div { "after" }
			end

			private def cache_store = CACHE_STORE
		end
	end
end
