# frozen_string_literal: true

module EquivalenceCases
	module LexicalSetConstant
		module Set
			def self.[](*) = ["custom"]
		end

		class LexicalSetConstant < Phlex::HTML
			def view_template
				div(class: Set["a", "b"]) { "x" }
				div(class: ::Set["a", "b"]) { "y" }
			end
		end
	end
end
