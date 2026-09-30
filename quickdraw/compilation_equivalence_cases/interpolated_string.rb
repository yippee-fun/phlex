# frozen_string_literal: true

module EquivalenceCases
	module InterpolatedString
		class InterpolatedString < Phlex::HTML
			def view_template
				name = "Joel"
				@ivar = "Will"
				h1 { "Hello, #{name}!" }
				h2 { "Hello, #@ivar!" } # rubocop:disable Style/VariableInterpolation
				h3 { "Hello #{"#{name}"}" } # rubocop:disable Style/RedundantInterpolation
			end
		end
	end
end
