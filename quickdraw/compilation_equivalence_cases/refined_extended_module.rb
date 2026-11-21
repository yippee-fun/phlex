# frozen_string_literal: true

module EquivalenceCases
	module RefinedExtendedModule
		module Label; end

		module Loud
			refine(Label) { def include?(*) = raise("refined") }
		end
	end
end

using EquivalenceCases::RefinedExtendedModule::Loud

module EquivalenceCases
	module RefinedExtendedModule
		class RefinedExtendedModule < Phlex::HTML
			def view_template
				div(title: String.new("x").extend(Label))
			end
		end
	end
end
