# frozen_string_literal: true

module EquivalenceCases
	module UnreachableUnsafeAttribute
		class UnreachableUnsafeAttribute < Phlex::HTML
			def view_template
				div { "before" }
				if false
					div(onclick: "alert(1)")
				end
				div { "after" }
			end
		end
	end
end
