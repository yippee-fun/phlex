# frozen_string_literal: true

module EquivalenceCases
	module Ruby2Keywords
		class Ruby2Keywords < Phlex::HTML
			def view_template
				delegate(:div, class: "x") { "y" }
			end

			ruby2_keywords def delegate(name, *args, &block)
				__send__(name, *args, &block)
			end
		end
	end
end
