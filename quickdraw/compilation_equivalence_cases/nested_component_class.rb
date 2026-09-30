# frozen_string_literal: true

module EquivalenceCases
	module NestedComponentClass
		class Outer < Phlex::HTML
			class Inner < Phlex::HTML
				def view_template = span { "inner" }
			end

			def view_template
				div { render Inner.new }
			end
		end
	end
end
