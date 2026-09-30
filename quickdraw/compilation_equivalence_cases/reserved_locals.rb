# frozen_string_literal: true

module EquivalenceCases
	module ReservedLocals
		class ReservedLocals < Phlex::HTML
			def view_template
				__phlex_done_1__ = "mine"
				div { helper }
				plain __phlex_done_1__
				other
			end

			def helper = "helped"

			def other = span { "compiled" }
		end
	end
end
