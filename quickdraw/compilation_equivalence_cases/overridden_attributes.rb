# frozen_string_literal: true

module EquivalenceCases
	module OverriddenAttributes
		class OverriddenAttributes < Phlex::HTML
			def view_template
				div(**{ id: "x" }) # rubocop:disable Style/RedundantDoubleSplatHashBraces
				extra = { class: "c" }
				span(id: "y", **extra) { "z" }
				img(**Hash.new(["default"]))
				img(**{})
			end

			private def __attributes__(_attributes) = " custom"
		end
	end
end
