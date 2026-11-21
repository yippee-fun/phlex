# frozen_string_literal: true

module EquivalenceCases
	module DirectAttributeAppends
		# Changes the string it was given when it's serialised.
		class Mutator
			def initialize(string) = @string = string

			def to_h
				@string << " changed"
				{ key: "value" }
			end
		end

		class Loud < String
			def include?(other)
				raise "loud" if start_with?("raise")

				super
			end
		end

		class DirectAttributeAppends < Phlex::HTML
			def self.equivalence_scenarios
				{
					"quoted" => -> (klass) { klass.new(%(say "hi")).call },
					"loud" => -> (klass) { klass.new(Loud.new("raise")).call },
					"true" => -> (klass) { klass.new(true).call },
					"fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) },
				}
			end

			def initialize(value = "plain")
				@value = value
			end

			def view_template
				name = +"name"
				div(title: name, data: Mutator.new(name)) { "a" }
				other = +"other"
				div(data: { a: other, b: Mutator.new(other) })
				input(value: @value, title: @value, class: "c")
				a(href: "/posts/#{@value}", title: @value)
				fragment(:f) { span(title: @value) }
			rescue RuntimeError => error
				plain "rescued #{error.message}"
			end
		end
	end
end
