# frozen_string_literal: true

module EquivalenceCases
	module ReopenedSetConstant
		class ReopenedSetConstant < Phlex::HTML
			def view_template
				with_standard_set
				with_custom_set
			end

			def with_standard_set
				div(class: Set["a", "b"]) { "standard" }
			end
		end

		module CustomSetScope
			module Set
				def self.[](*) = ["custom"]
			end

			# Reopened inside a scope with its own Set, which the class's name
			# doesn't reveal.
			class ::EquivalenceCases::ReopenedSetConstant::ReopenedSetConstant
				def with_custom_set
					div(class: Set["a", "b"]) { "custom" }
				end
			end
		end
	end
end
