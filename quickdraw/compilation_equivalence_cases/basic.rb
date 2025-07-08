# frozen_string_literal: true

class Basic < Phlex::HTML
	def view_template
		h1 { "Hello" }
		br
		br(class: "my-class")
	end
end
