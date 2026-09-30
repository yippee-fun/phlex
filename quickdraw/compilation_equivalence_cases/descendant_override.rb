# frozen_string_literal: true

module EquivalenceCases
	module DescendantOverride
		class Base < Phlex::HTML
			def view_template
				div { "hi" }
				plain "text"
				span { "kept" }
			end
		end

		class Child < Base
			def div(**, &)
				plain("override")
			end

			def plain(content)
				super("[#{content}]")
			end
		end

		class Grandchild < Child
		end
	end
end
