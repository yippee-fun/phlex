# frozen_string_literal: true

module EquivalenceCases
	module RefinedStringSubclassModule
		module Quoting; end

		class Title < String
			include Quoting
		end

		module Loud
			refine(Quoting) { def include?(*) = raise("refined") }
		end
	end
end

using EquivalenceCases::RefinedStringSubclassModule::Loud

module EquivalenceCases
	module RefinedStringSubclassModule
		class RefinedStringSubclassModule < Phlex::HTML
			def view_template
				div(title: Title.new("x"))
			end
		end
	end
end
