# frozen_string_literal: false

module EquivalenceCases
	module ExpectedMutableLocals
		class ExpectedMutableLocals < Phlex::HTML
			def view_template
				label = "a"
				label << "b"
				div { label }
			end
		end
	end
end
