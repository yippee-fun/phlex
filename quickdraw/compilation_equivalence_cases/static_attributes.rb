# frozen_string_literal: true

module EquivalenceCases
	module StaticAttributes
		class StaticAttributes < Phlex::HTML
			def view_template
				div(class: "a", id: "b", data: { x: 1 }) { "hi" }
				a(href: "/x") { "link" }
				input(type: "text", disabled: true, hidden: false, tabindex: 0)
				div("data-x" => 1, class: nil, "str" => "v") { "k" } # rubocop:disable Style/HashSyntax
			end
		end
	end
end
