# frozen_string_literal: true

module EquivalenceCases
	module YieldArguments
		class Other < Phlex::HTML
			def view_template
				div(class: "other") { yield(self, "arg") }
			end
		end

		class YieldArguments < Phlex::HTML
			def self.equivalence_scenarios = { "with block" => -> (klass) { klass.new.call { "blk" } } }

			def view_template(&block)
				div { |el| el.span { "x" } }
				render Other.new { |x, arg| x.b { arg } }
				render(Other.new) { |x, arg| x.i { arg } }
				section { yield }
				article { yield_block(&block) }
			end

			def yield_block
				p { yield }
			end
		end

		class WithBlockMethod < Phlex::HTML
			def view_template
				wrapper { span { "inner" } }
				wrapper { "text" }
			end

			def wrapper(&)
				div(class: "wrap") { yield }
			end
		end
	end
end
