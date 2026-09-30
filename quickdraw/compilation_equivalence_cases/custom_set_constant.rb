# frozen_string_literal: true

module EquivalenceCases
	module CustomSetConstant
		class CustomSetConstant < Phlex::HTML
			module Set
				def self.[](*) = ["custom"]
			end

			def view_template
				div(class: Set["a", "b"]) { "x" }
				div(class: ::Set["a", "b"]) { "y" }
			end
		end
	end
end
