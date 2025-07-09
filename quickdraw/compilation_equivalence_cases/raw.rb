# frozen_string_literal: true

class Raw < Phlex::HTML
	def view_template
		p { "output before" }
		raw(safe("raw output in the middle"))
		p { "output after" }
	end
end
