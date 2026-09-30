# frozen_string_literal: true

module EquivalenceCases
	module PositionalArguments
		class PositionalArguments < Phlex::HTML
			def view_template
				div("x") { "y" }
			end
		end
	end
end
