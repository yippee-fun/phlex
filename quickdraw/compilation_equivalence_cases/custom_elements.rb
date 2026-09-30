# frozen_string_literal: true

module EquivalenceCases
	module CustomElements
		class CustomElements < Phlex::HTML
			register_element :my_el

			def view_template
				my_el(class: "c") { "custom" }
				div { "shadowed" }
				span(class: "s") { "span" }
			end

			def div(**attrs, &)
				span(**attrs, id: "shadow", &)
			end
		end

		class ShadowedVoid < Phlex::HTML
			def view_template
				img(src: "a")
			end

			def img(**)
				span { "not an img" }
			end
		end
	end
end
