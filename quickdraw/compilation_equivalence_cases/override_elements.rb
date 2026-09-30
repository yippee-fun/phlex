# frozen_string_literal: true

module EquivalenceCases
	module OverrideElements
		class OverrideElements < Phlex::HTML
			def view_template
				input(type: "email")

				h1
				input(type: "email")
				div do
					input(type: "email")
				end
			end

			def input(**)
				plain("not-an-input")
			end
		end
	end
end
