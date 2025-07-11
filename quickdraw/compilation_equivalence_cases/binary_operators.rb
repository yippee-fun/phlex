# frozen_string_literal: true

class BinaryOperators < Phlex::HTML
	def view_template
		# Test subtraction
		@a = 10
		@b = 5
		
		span(x_text: "renderTotal()") { number_to_currency(@a - @b) }
		
		# Test other binary operators
		div { @a + @b }
		div { @a * @b }
		div { @a / @b }
		div { @a % @b }
		div { @a ** @b }
	end
	
	def number_to_currency(amount)
		"$#{amount}"
	end
end