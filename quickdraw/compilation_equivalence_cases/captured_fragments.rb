# frozen_string_literal: true

module EquivalenceCases
	module CapturedFragments
		class View < Phlex::HTML
			def initialize(cache_store = Phlex::FIFOCacheStore.new)
				@cache_store = cache_store
			end

			def view_template
				captured = capture { fragment("before") { span { "before" } } }
				low_level_cache("page") do
					plain "前"
					raw safe(captured)
					div do
						safe(capture { fragment("implicit") { span { "implicit" } } })
					end
					div(id: "wrapper") do
						safe(capture { fragment("attributes") { span { "attributes" } } })
					end
					comment do
						safe(capture { fragment("comment") { span { "comment" } } })
					end
				end
			end

			def self.equivalence_scenarios
				%w[before implicit attributes comment].to_h do |name|
					[name, -> (klass) do
						store = Phlex::FIFOCacheStore.new
						2.times.map { klass.new(store).call(fragments: [name]) }
					end]
				end
			end

			private attr_reader :cache_store
		end
	end
end
