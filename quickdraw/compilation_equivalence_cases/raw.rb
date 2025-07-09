# frozen_string_literal: true

class Raw < Phlex::HTML
	def view_template
		p { "output before" }
		raw(safe("<h1>raw output in the middle</h1>"))
		p { "output after" }
	end
end
