# frozen_string_literal: true

class UnaryNot < Phlex::HTML
	def view_template
		result = !some_thing?
		plain result.to_s
	end

	def some_thing?
		false
	end
end