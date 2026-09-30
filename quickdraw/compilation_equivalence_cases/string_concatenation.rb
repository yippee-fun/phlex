# frozen_string_literal: true

module EquivalenceCases
	module StringConcatenation
		class StringConcatenation < Phlex::HTML
			def initialize
				@x = "<x>"
			end

			def view_template
				div { "a" "b#{@x}" } # rubocop:disable Lint/ImplicitStringConcatenation
				plain "c" "d#{@x}" # rubocop:disable Lint/ImplicitStringConcatenation
				div(title: "e" "f#{@x}") { "t" } # rubocop:disable Lint/ImplicitStringConcatenation
			end
		end
	end
end
