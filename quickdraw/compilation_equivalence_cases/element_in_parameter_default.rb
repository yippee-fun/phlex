# frozen_string_literal: true

module EquivalenceCases
	module ElementInParameterDefault
		class ElementInParameterDefault < Phlex::HTML
			def view_template
				heading
				heading("given")
			end

			def heading(text = (hr; "default"))
				h1 { text }
			end
		end
	end
end
