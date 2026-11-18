# frozen_string_literal: true

module EquivalenceCases
	module SameLineUnrelated
		# Two definitions share a line here, but neither is a component's live
		# method, so they don't stop the component below from compiling.
		class Helpers; def label = "label"; def other = "other"; end

		class SameLineUnrelated < Phlex::HTML
			def view_template
				div { Helpers.new.label }
			end
		end
	end
end
