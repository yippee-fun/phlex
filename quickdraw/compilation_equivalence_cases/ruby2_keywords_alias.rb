# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsAlias
		# Marking the alias marks the body it shares with `delegate`, which
		# compiling `delegate` would lose.
		class Ruby2KeywordsAlias < Phlex::HTML
			def view_template
				delegate(name: "kwargs")
			end

			def delegate(*args)
				div { target(*args) }
			end

			alias_method :forward, :delegate
			ruby2_keywords :forward

			def target(*, name: "positional") = name
		end
	end
end
