# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsReopened
		class Ruby2KeywordsReopened < Phlex::HTML
			def view_template
				delegate(:div, class: "x") { "y" }
			end

			def delegate(name, *args, &block)
				span { "delegating" }
				__send__(name, *args, &block)
			end
		end

		# The mark sits in a reopening, a different class statement.
		class Ruby2KeywordsReopened
			ruby2_keywords :delegate
		end
	end
end
