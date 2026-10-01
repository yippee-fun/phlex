# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsSplat
		class Ruby2KeywordsSplat < Phlex::HTML
			def view_template
				delegate(:div, class: "x") { "y" }
			end

			def delegate(name, *args, &block)
				__send__(name, *args, &block)
			end

			ruby2_keywords(*[:delegate])
		end
	end
end
