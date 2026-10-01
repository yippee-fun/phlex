# frozen_string_literal: true

module EquivalenceCases
	module Refinement
		module Shout
			refine(String) { def shout = upcase + "!" }
		end
	end
end

using EquivalenceCases::Refinement::Shout

module EquivalenceCases
	module Refinement
		class Refined < Phlex::HTML
			def view_template
				div { "hi".shout }
				plain "x".shout
				div(title: "t".shout)
			end
		end
	end
end
