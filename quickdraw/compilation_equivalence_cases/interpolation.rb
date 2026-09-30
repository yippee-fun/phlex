# frozen_string_literal: true

module EquivalenceCases
	module Interpolation
		class Interpolation < Phlex::HTML
			def initialize
				@name = "Wor<ld"
			end

			def name = @name

			def view_template
				h1 { "Hello #{name}" }
				h2 { "Hi #@name!" } # rubocop:disable Style/VariableInterpolation
				h3 { "n=#{1 + 1}" }
				p { <<~TEXT }
					Heredoc #{name}
					line 2 <
				TEXT
				div { "a" "b" } # rubocop:disable Lint/ImplicitStringConcatenation
			end
		end
	end
end
