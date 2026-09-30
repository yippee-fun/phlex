# frozen_string_literal: true

module EquivalenceCases
	module BlockNext
		class BlockNext < Phlex::HTML
			def view_template
				div { plain "a"; next }
				div { "after" }
			end
		end
	end
end
