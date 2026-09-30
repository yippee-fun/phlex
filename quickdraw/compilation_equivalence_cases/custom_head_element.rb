# frozen_string_literal: true

module EquivalenceCases
	module CustomHeadElement
		class CustomHeadElement < Phlex::HTML
			register_element :page_head, tag: "head"

			def view_template
				html do
					page_head { title { "T" } }
					body { "B" }
				end
			end
		end
	end
end
