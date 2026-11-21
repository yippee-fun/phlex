# frozen_string_literal: true

module EquivalenceCases
	module UnrelatedRefinement
		module Irrelevant
			refine(Object) { def irrelevant = "irrelevant" }
			refine(Object) { def tap = super } # rubocop:disable Lint/UselessMethodDefinition
			refine(StandardError.singleton_class) { def ===(other) = super } # rubocop:disable Lint/UselessMethodDefinition
		end
	end
end

using EquivalenceCases::UnrelatedRefinement::Irrelevant

module EquivalenceCases
	module UnrelatedRefinement
		class UnrelatedRefinement < Phlex::HTML
			def view_template
				div { irrelevant }
			end
		end
	end
end
