# frozen_string_literal: true

module EquivalenceCases
	module HiddenRefinements
		module NoQuotes
			refine(String) { def include?(*) = false }

			def self.refinements = []
		end
	end
end

using EquivalenceCases::HiddenRefinements::NoQuotes

module EquivalenceCases
	module HiddenRefinements
		class HiddenRefinements < Phlex::HTML
			def view_template
				div(title: %(say "hi"))
			end
		end
	end
end
