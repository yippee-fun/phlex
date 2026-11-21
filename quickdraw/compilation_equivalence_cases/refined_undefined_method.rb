# frozen_string_literal: true

module EquivalenceCases
	module RefinedUndefinedMethod
		module Unprintable
			refine(Integer) { undef_method :to_s }
		end
	end
end

using EquivalenceCases::RefinedUndefinedMethod::Unprintable

module EquivalenceCases
	module RefinedUndefinedMethod
		class RefinedUndefinedMethod < Phlex::HTML
			def initialize
				@count = 3
			end

			def view_template
				div(title: @count)
			end
		end
	end
end
