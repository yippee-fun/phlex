# frozen_string_literal: true

module EquivalenceCases
	module ExceptionClasses
		class ExceptionClasses < Phlex::HTML
			def view_template
				div { raise NotImplementedError, "nope" }
			end
		end
	end
end
