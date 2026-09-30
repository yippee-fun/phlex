# frozen_string_literal: true

module EquivalenceCases
	module ConstantEvaluation
		class ConstantEvaluation < Phlex::HTML
			def self.equivalence_scenarios
				{
					"other fragment" => -> (klass) { klass.new.call(fragments: ["other"]) },
				}
			end

			def view_template
				fragment("other") { p { "selected" } }
				div(class: MissingConstant) { "x" }
			end
		end
	end
end
