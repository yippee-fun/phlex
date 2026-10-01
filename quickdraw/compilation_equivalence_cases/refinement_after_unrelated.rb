# frozen_string_literal: true

module EquivalenceCases
	module RefinementAfterUnrelated
		module Shout
			refine(String) { def shout = upcase + "!" }
		end

		# A definition above the `using` that isn't compiled doesn't need the
		# refinement reproduced for it.
		module Unrelated
			def unrelated = "unrelated"
		end

		# A component above the `using` whose method compiles to nothing is left
		# alone too.
		class Uncompiled < Phlex::HTML
			def view_template = plain(label)
			def label = "uncompiled"
		end
	end
end

using EquivalenceCases::RefinementAfterUnrelated::Shout

module EquivalenceCases
	module RefinementAfterUnrelated
		class RefinementAfterUnrelated < Phlex::HTML
			def view_template
				div { "hi".shout }
			end
		end
	end
end
