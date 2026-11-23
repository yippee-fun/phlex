# frozen_string_literal: true

module EquivalenceCases
	module AnimationReferences
		# SVG animation values are references, and `values` is a list whose later
		# entries can be script URLs whatever the literal prefix is.
		class AnimationReferences < Phlex::SVG
			VALUES = [
				"#b",
				"javascript:alert(1)",
				";javascript:alert(1)",
				"&#59;javascript:alert(1)",
				"&semi;javascript:alert(1)",
				"&zz;javascript:alert(1)",
				"&TAB;javascript:alert(1)",
				"&#38;zz;javascript:alert(1)",
				"0;10",
				%(say "<hi>"),
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end
			end

			def initialize(value)
				@value = value
			end

			def view_template
				svg do
					a(href: "#a") do
						set(attributeName: "href", to: @value)
						set(attributeName: "href", to: "#a#{@value}")
						animate(attributeName: "href", from: "#a#{@value}", to: "#b")
						animate(attributeName: "href", by: @value)
						animate(attributeName: "href", values: @value)
						animate(attributeName: "href", values: "#a#{@value}")
						animate(attributeName: "href", values: "#a;#{@value}")
						animate(attributeName: "href", "values" => "#a#{@value}")
						animate(attributeName: "href", values: [@value, "#a"])
						animate(attributeName: "href", values: "#a;#b")
						a("x:href": @value, "x:to": "#a#{@value}")
						text { "x" }
					end
				end
			end
		end
	end
end
