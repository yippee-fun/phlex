# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsCopy
		# A copy made by `define_method` shares its body with `delegate` just as
		# an alias does, so marking the copy marks `delegate` too.
		class Ruby2KeywordsCopy < Phlex::HTML
			def view_template
				delegate(name: "kwargs")
			end

			def delegate(*args)
				div { target(*args) }
			end

			def target(*, name: "positional") = name
		end

		class Copier < Ruby2KeywordsCopy
			define_method(:forward, Ruby2KeywordsCopy.instance_method(:delegate))
			ruby2_keywords :forward
		end
	end
end
