# frozen_string_literal: true

module EquivalenceCases
	module ConditionalUsing
		module Shout
			refine(String) { def shout = upcase + "!" }
		end
	end
end

# Copied as a plain `using`, this would refine strings the original didn't.
using EquivalenceCases::ConditionalUsing::Shout if ENV.key?("PHLEX_NEVER_SET")

module EquivalenceCases
	module ConditionalUsing
		class ConditionalUsing < Phlex::HTML
			def view_template
				div { "hi".respond_to?(:shout).to_s }
			end
		end
	end
end
