# frozen_string_literal: true

module EquivalenceCases
	module RefinedStringSubclass
		class Title < String; end

		module Loud
			refine(Title) { def include?(*) = raise("refined") }
		end
	end
end

using EquivalenceCases::RefinedStringSubclass::Loud

module EquivalenceCases
	module RefinedStringSubclass
		class RefinedStringSubclass < Phlex::HTML
			def view_template
				div(title: Title.new("x"))
			end
		end
	end
end
