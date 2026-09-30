# frozen_string_literal: true

module EquivalenceCases
	module ExpressionPosition
		class ExpressionPosition < Phlex::HTML
			def view_template
				ul do
					%w[a b c].each { |item| item_row(item) }
				end

				result = div { "assigned" }
				plain result.inspect

				list = [span { "in array" }, 1]
				plain list.inspect

				plain(div { "as argument" }.inspect)
				@flag && strong { "and" }
			end

			def item_row(item)
				return li(class: "last") { plain "last #{item}" } if item == "c"

				li { item }
			end
		end
	end
end
