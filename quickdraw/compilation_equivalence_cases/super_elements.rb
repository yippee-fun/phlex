# frozen_string_literal: true

module EquivalenceCases
	module SuperElements
		class Base < Phlex::HTML
			def initialize(cache_store = Phlex::FIFOCacheStore.new)
				@cache_store = cache_store
			end

			def view_template
				head { title { "Head" } }
				header(id: "named") { "In a block" }
				footer(id: "anonymous") { "In a block" }
				h1 { "Title" }
				h1(id: "main") { strong { "Bold" } }
				h2(class: "extra") { "Implicit" }
				h3 { "Zsuper" }
				h4
				h5(class: "x") { "No arguments" }
				h6 { "Literal block" }
				br(class: "x")
				section { "Aliased" }
				region { "Alias" }
				aside { "Positional" }
				fragment("cached") do
					low_level_cache("key") do
						h1(id: "inside") { "Cached" }
						h3 { "Cached zsuper" }
					end
				end
			end

			def head(**attrs, &)
				super(**attrs, &)
			end

			def header(**attrs)
				div { super }
			end

			def footer(**, &)
				div { super }
			end

			def h1(**attrs, &)
				super(**mix(attrs, class: "font-bold"), &)
			end

			def h2(**attrs)
				super(**attrs, id: "implicit")
			end

			def h3(**)
				plain "|"
				super
			end

			def h4 = super

			def h5(**attrs, &)
				super(&)
			end

			def h6(**attrs)
				super(**attrs) { plain "Replaced" }
			end

			def br(**attrs)
				super(**attrs, data: { void: true })
			end

			def section(**attrs, &)
				super(**attrs, class: "aliased", &)
			end
			alias_method :region, :section

			def aside(**attrs, &)
				super("positional", &)
			rescue ArgumentError => e
				plain e.class.name
			end

			def self.equivalence_scenarios = {
				"fragment" => -> (klass) do
					store = Phlex::FIFOCacheStore.new
					2.times.map { klass.new(store).call(fragments: ["cached"]) }
				end,
			}

			private attr_reader :cache_store
		end

		class Child < Base
			def h1(**attrs, &)
				span { super }
			end

			def h2(**attrs)
				super
				plain "after"
			end
		end
	end
end
