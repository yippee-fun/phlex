# frozen_string_literal: true

module EquivalenceCases
	module Plain
		class Plain < Phlex::HTML
			def view_template
				local_variable = "good"
				plain "Greetings "
				plain local_variable
				plain "sir!"
			end
		end
	end
end
