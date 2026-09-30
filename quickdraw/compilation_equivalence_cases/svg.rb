# frozen_string_literal: true

module EquivalenceCases
	module Svg
		class Svg < Phlex::SVG
			def view_template
				svg(viewbox: "0 0 10 10") { path(d: "M0 0") }
			end
		end

		class InHtml < Phlex::HTML
			def view_template
				div { svg(viewbox: "0 0 1 1") { |s| s.path(d: "M0 0") } }
			end
		end
	end
end
