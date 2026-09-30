# frozen_string_literal: true

module EquivalenceCases
	module CustomVoidElement
		class CustomVoidElement < Phlex::HTML
			__register_void_element__ def my_void(**) = nil

			def view_template
				my_void(class: "c")
				my_void
				br { span { "ignored" } }
			end
		end
	end
end
