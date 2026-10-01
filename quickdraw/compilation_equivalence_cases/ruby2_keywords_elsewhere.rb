# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsElsewhere
		# Shares the file with the component but isn't compiled, so its flag
		# doesn't matter.
		class Legacy
			ruby2_keywords def delegate(*args, &block) = target(*args, &block)

			def target(*, **) = nil
		end

		class Ruby2KeywordsElsewhere < Phlex::HTML
			def view_template
				div { "compiled" }
			end
		end
	end
end
