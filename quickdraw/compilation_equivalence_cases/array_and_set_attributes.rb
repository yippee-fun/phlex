# frozen_string_literal: true

module EquivalenceCases
	module ArrayAndSetAttributes
		class ArrayAndSetAttributes < Phlex::HTML
			def view_template
				div(class: ["a", "b"]) { "arr" }
				div(class: Set["a", "b"]) { "set" }
				div(class: ["a", nil, :sym, 1]) { "mixed" }
				div(class: ["a", ["b", "c"]]) { "nested" }
				div(class: ["a", false, [false, "b"]]) { "false" }
				div(class: [false]) { "only false" }
				div(class: ["a", (@items.nil? && false)]) { "dynamic false" }
				div(style: ["color: red", false]) { "style false" }
				div(style: { color: false, top: 0 }) { "style hash false" }
				div(style: { color: (@items.nil? && false) }) { "dynamic style false" }
			end
		end
	end
end
