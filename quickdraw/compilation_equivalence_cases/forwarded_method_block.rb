# frozen_string_literal: true

module EquivalenceCases
	module ForwardedMethodBlock
		# Renders only the first time it's asked.
		class OnceState < Phlex::SGML::State
			def should_render? = (@reads = @reads.to_i + 1) == 1
		end

		# Suspends while its attributes are serialised, then raises.
		class FiberAttribute < Phlex::HTML
			def view_template
				fiber = Fiber.new { wrap }
				fiber.resume
				capture { fiber.resume }
			rescue RuntimeError
				plain "rescued"
			end

			def wrap(&) = div(data: self, &)

			def to_h
				Fiber.yield
				raise "bad"
			end
		end

		class ForwardedMethodBlock < Phlex::HTML
			VALUES = [
				"text <b>",
				:a_symbol,
				1,
				1.5,
				nil,
				Object.new,
				Phlex::SGML::SafeValue.new("<i>"),
				"safe".dup.extend(Phlex::SGML::SafeObject),
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end.merge(
					"fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) },
					"bad attribute" => -> (klass) { klass.new("x", id: Object.new).call },
					"rendering checked once" => -> (klass) {
						state = OnceState.new(output_buffer: +"", fragments: nil)
						klass.new("x").internal_call(state:)
						state.buffer
					},
				)
			end

			def initialize(value, id: "w")
				@value = value
				@id = id
			end

			def view_template
				value = @value
				wrapper { value }
				wrapper { span { "written" }; "ignored" }
				wrapper
				catch(:out) { wrapper { throw :out } }
				[1, 2].each { |i| wrapper { break if i == 1 } }
				fiber = Fiber.new { wrapper { Fiber.yield; "resumed" } }
				fiber.resume
				plain capture { fiber.resume }
				fragment(:f) { wrapper { "in fragment" } }
				wrapper { raise ArgumentError }
			rescue => error
				plain "rescued #{error.class}"
			end

			def wrapper(&)
				article(id: @id, class: "w", &)
			end
		end
	end
end
