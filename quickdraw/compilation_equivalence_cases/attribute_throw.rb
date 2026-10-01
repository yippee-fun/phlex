# frozen_string_literal: true

module EquivalenceCases
	module AttributeThrow
		class Thrower
			def to_h = throw(:skip)
		end

		class AttributeThrow < Phlex::HTML
			def view_template
				catch(:skip) { div(data: Thrower.new) }
				catch(:skip) { div(data: Thrower.new) { "content" } }
				catch(:skip) { img(src: "a.png", data: Thrower.new) }
				catch(:skip) { div(id: "x", **{ data: Thrower.new }) }
				catch(:skip) { div(class: "a", data: Thrower.new, id: "b") }
				plain "after"
			end
		end
	end
end
