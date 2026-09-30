# frozen_string_literal: true

module EquivalenceCases
	module AttributeErrors
		class AttributeErrors < Phlex::HTML
			def initialize
				@bad = Object.new
			end

			def view_template
				p { "before" }
				div(class: @bad) { "x" }
			rescue Phlex::ArgumentError
				plain "rescued"
			end
		end
	end
end
