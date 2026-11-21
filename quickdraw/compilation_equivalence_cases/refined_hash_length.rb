# frozen_string_literal: true

module EquivalenceCases
	module RefinedHashLength
		module Empty
			refine(Hash) { def length = 0 }
		end
	end
end

using EquivalenceCases::RefinedHashLength::Empty

module EquivalenceCases
	module RefinedHashLength
		class RefinedHashLength < Phlex::HTML
			def view_template
				attributes = { id: "x" }
				div(**attributes)
			end
		end
	end
end
