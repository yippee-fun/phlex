# frozen_string_literal: true

module EquivalenceCases
	module RegisteredElementTag
		class Base < Phlex::HTML
			register_element :my_el, tag: "custom-el"
			__register_void_element__ :my_void
		end

		class HTML < Base
			register_element :foo

			def view_template
				foo { "method" }
				tag(:foo) { "tag" }
				my_el(class: "c") { "method" }
				tag(:my_el, class: "c") { "tag" }
				my_void(id: "a")
				tag(:my_void, id: "a")
			end
		end

		module SVGElements
			extend Phlex::SGML::Elements

			register_element :foo
			__register_void_element__ :my_void
		end

		class SVG < Phlex::SVG
			include SVGElements

			def view_template
				foo { "method" }
				tag(:foo) { "tag" }
				my_void
				tag(:my_void)
			end
		end
	end
end
