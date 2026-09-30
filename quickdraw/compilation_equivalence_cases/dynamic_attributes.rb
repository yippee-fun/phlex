# frozen_string_literal: true

module EquivalenceCases
	module DynamicAttributes
		class DynamicAttributes < Phlex::HTML
			def initialize
				@cls = "dyn"
				@attrs = { id: "z", "data-y" => 2 } # rubocop:disable Style/HashSyntax
			end

			def view_template
				div(class: @cls) { "1" }
				div(**@attrs) { "2" }
				cls = "local"
				div(class: cls, id: "x") { "3" }
				div(id: "y", **@attrs)
				span(class: [@cls, "b"])
				div(id: (plain "x"; "a")) { "4" }
			end
		end
	end
end
