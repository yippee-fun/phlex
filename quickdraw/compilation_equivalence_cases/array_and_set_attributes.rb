# frozen_string_literal: true

module EquivalenceCases
	module ArrayAndSetAttributes
		class ArrayAndSetAttributes < Phlex::HTML
			def view_template
				div(class: ["a", "b"]) { "arr" }
				div(class: Set["a", "b"]) { "set" }
				div(class: ["a", nil, :sym, 1]) { "mixed" }
				div(class: ["a", ["b", "c"]]) { "nested" }
			end
		end
	end
end
