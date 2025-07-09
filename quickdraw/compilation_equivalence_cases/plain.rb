# frozen_string_literal: true

class Plain < Phlex::HTML
	def view_template
		local_variable = "good"
		plain "Greetings "
		plain local_variable
		plain "sir!"
	end
end
