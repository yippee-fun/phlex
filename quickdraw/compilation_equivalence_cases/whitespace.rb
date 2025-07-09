# frozen_string_literal: true

class Whitespace < Phlex::HTML
	def view_template
		h1 { "Hello" }
		whitespace
		h2 { "world" }
		br
		br
		p do
			plain "This sentence has"
			whitespace { em { "emphasis" } }
			plain "in it."
		end
	end
end
