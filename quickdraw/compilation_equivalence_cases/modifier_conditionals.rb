# frozen_string_literal: true

module EquivalenceCases
	module ModifierConditionals
		class ModifierConditionals < Phlex::HTML
			def initialize(flag: false)
				@flag = flag
				@content = "content"
			end

			def self.equivalence_scenarios
				{
					"flag on" => -> (klass) { klass.new(flag: true).call },
				}
			end

			def view_template
				b { "always" }
				span(class: "x") { plain @content } if @flag
				em { @content } unless @flag
				count = 0
				p { plain "loop #{count += 1}" } while count < 2 && @flag
				strong { count.to_s } until true
				i { "end" }
			end
		end
	end
end
