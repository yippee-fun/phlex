# frozen_string_literal: true

module EquivalenceCases
	module ReregisteredElement
		class ReregisteredElement < Phlex::HTML
			__register_void_element__ def toggle(**) = nil
			register_element :toggle

			def view_template
				toggle(class: "c")
				toggle { "content" }
			end
		end
	end
end
