# frozen_string_literal: true

module EquivalenceCases
	module InlineSvg
		class InlineSvg < Phlex::HTML
			def self.equivalence_scenarios
				{
					"fragment" => -> (klass) { klass.new.call(fragments: [:f]) },
					"bad class" => -> (klass) { klass.new(Object.new).call },
				}
			end

			def initialize(icon_class = "icon")
				@icon_class = icon_class
				@d = "M6 18L18 6"
			end

			def view_template
				svg(viewBox: "0 0 24 24", class: "icon") { |s| s.path(d: "M5 13l4 4L19 7") }
				svg(class: @icon_class) do |s|
					s.g(fill: "none") do
						s.circle(cx: 12, cy: 12, r: 3)
						s.text { "Label <b>" }
						s.title { :a_symbol }
					end
					s.clipPath(id: "c")
				end
				svg { |s| s.path(d: @d) }
				svg { |s| s.plain "text" }
				svg
				svg { |_s| } # rubocop:disable Lint/EmptyBlock
				fragment(:f) { svg { |s| s.path(d: "in fragment") } }
			rescue Phlex::ArgumentError
				plain "rescued"
			end
		end
	end
end
