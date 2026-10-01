# frozen_string_literal: true

module EquivalenceCases
	module ForwardedBlock
		class ForwardedBlock < Phlex::HTML
			def view_template
				div(&content_block)
				div(class: "x", &content_block)
				section(&nil)
				section(class: "y", &nil)
				wrapper { "in" }
				wrapper
			end

			# Writes to the buffer before the element opens, and the block it
			# returns writes inside the element.
			def content_block
				plain "before"
				proc { span { "inside" }; "value" }
			end

			def wrapper(&)
				article(id: "w", &)
			end
		end

		class InvalidAttributeWithNilBlock < Phlex::HTML
			def view_template
				block = nil
				div(class: Object.new, &block)
			rescue Phlex::ArgumentError
				plain "rescued"
			end
		end
	end
end
