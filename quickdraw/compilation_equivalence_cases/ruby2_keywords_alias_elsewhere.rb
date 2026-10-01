# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsAliasElsewhere
		# Marks a method of its own that has the alias's name. That doesn't mark
		# the component's alias, but telling which class a mark is in would mean
		# evaluating the class's statements, so marks are matched by name and
		# `delegate` is refused.
		class Legacy
			ruby2_keywords def forward(*args, &block) = target(*args, &block)

			def target(*, **) = nil
		end

		class Ruby2KeywordsAliasElsewhere < Phlex::HTML
			def view_template
				forward
			end

			def delegate
				div { "compiled" }
			end

			alias_method :forward, :delegate
		end
	end
end
