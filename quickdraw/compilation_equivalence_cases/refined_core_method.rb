# frozen_string_literal: true

module EquivalenceCases
	module RefinedCoreMethod
		module NoQuotes
			refine(String) { def include?(*) = false }
		end
	end
end

using EquivalenceCases::RefinedCoreMethod::NoQuotes

module EquivalenceCases
	module RefinedCoreMethod
		class RefinedCoreMethod < Phlex::HTML
			def view_template
				div(title: %(say "hi"))
			end
		end
	end
end
