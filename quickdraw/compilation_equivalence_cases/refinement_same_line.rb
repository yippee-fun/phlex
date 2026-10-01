# frozen_string_literal: true

module EquivalenceCases
	module RefinementSameLine
		module Shout
			refine(String) { def shout = upcase + "!" }
		end
	end
end

# The `using` follows the definition on its line, so the definition doesn't
# see the refinement.
class EquivalenceCases::RefinementSameLine::RefinementSameLine < Phlex::HTML; def view_template = div { "hi".respond_to?(:shout).to_s }; end; using EquivalenceCases::RefinementSameLine::Shout
