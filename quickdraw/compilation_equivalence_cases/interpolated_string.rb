# frozen_string_literal: true

class InterpolatedString < Phlex::HTML
	def view_template
		name = "Joel"
		@ivar = "Will"
		h1 { "Hello, #{name}!" }
		h2 { "Hello, #@ivar!" } # rubocop:disable Style/VariableInterpolation
		h3 { "Hello #{"#{name}"}" }
	end
end
