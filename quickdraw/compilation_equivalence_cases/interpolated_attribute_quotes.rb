# frozen_string_literal: true

module EquivalenceCases
	module InterpolatedAttributeQuotes
		class InterpolatedAttributeQuotes < Phlex::HTML
			def self.equivalence_scenarios
				{
					"quoted" => -> (klass) { klass.new(%(say "hi")).call },
					"invalid UTF-8" => -> (klass) { klass.new((+"\"\xFF").force_encoding(Encoding::UTF_8)).call },
					"UTF-16" => -> (klass) { klass.new(%("x").encode(Encoding::UTF_16LE)).call },
				}
			end

			def initialize(value = "plain")
				@value = value
			end

			def view_template
				div(title: "#{@value}") { "y" } # rubocop:disable Style/RedundantInterpolation
				div(title: "a #{@value}", id: "b-#{@value}") { "x" }
				input(value: "#{@value}#{@value}")
				plain($~.inspect)
			rescue Encoding::CompatibilityError
				plain "rescued"
			end
		end
	end
end
