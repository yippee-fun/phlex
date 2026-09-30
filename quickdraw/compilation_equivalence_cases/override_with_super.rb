# frozen_string_literal: true

module EquivalenceCases
	module OverrideWithSuper
		class OverrideWithSuper < Phlex::HTML
			def view_template
				a(href: "/") { "Home" }
				div { a(href: "/about") { "About" } }
				br(class: "x")
			end

			def a(**attributes, &)
				super(class: "link", **attributes, &)
			end

			def br(**)
				plain "|"
				super
			end
		end

		class Child < OverrideWithSuper
			def a(**, &)
				span { super }
			end
		end
	end
end
