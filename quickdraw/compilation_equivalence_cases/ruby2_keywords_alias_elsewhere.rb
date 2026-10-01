# frozen_string_literal: true

module EquivalenceCases
	module Ruby2KeywordsAliasElsewhere
		# Marks a method of its own that has the alias's name, which doesn't mark
		# the component's alias.
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
