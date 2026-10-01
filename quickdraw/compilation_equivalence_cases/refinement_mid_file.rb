# frozen_string_literal: true

module EquivalenceCases
	module RefinementMidFile
		module Shout
			refine(String) { def shout = upcase + "!" }
		end

		class Unrefined < Phlex::HTML
			def view_template
				div { "hi".respond_to?(:shout).to_s }
			end
		end
	end
end

using EquivalenceCases::RefinementMidFile::Shout

module EquivalenceCases
	module RefinementMidFile
		class Refined < Phlex::HTML
			def view_template
				div { "hi".shout }
			end
		end
	end
end
