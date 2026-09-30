# frozen_string_literal: true

module EquivalenceCases
	module Basic
		class Basic < Phlex::HTML
			def view_template
				h1 { "Hello" }
				br
				br(class: "my-class")
			end
		end
	end
end
