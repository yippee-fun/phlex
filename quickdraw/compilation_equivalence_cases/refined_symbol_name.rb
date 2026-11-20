# frozen_string_literal: true

module EquivalenceCases
	module RefinedSymbolName
		module Changed
			refine(Symbol) { def name = "changed" }
		end
	end
end

using EquivalenceCases::RefinedSymbolName::Changed

module EquivalenceCases
	module RefinedSymbolName
		class RefinedSymbolName < Phlex::HTML
			def view_template
				value = :ok
				div { value }
			end
		end
	end
end
