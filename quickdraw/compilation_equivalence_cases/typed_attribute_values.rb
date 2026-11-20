# frozen_string_literal: true

module EquivalenceCases
	module TypedAttributeValues
		class Loud < String
			def include?(other)
				raise "loud" if start_with?("raise")

				super
			end
		end

		class TypedAttributeValues < Phlex::HTML
			VALUES = [
				true,
				false,
				nil,
				"plain",
				%(say "hi"),
				:a_symbol,
				1,
				1.5,
				[:a, "b"],
				"x".encode(Encoding::UTF_16LE),
				"".encode(Encoding::UTF_16LE),
				"é".dup.force_encoding(Encoding::US_ASCII),
				Loud.new(%(loud "quote")),
				Loud.new("raise"),
				"safe".dup.extend(Phlex::SGML::SafeObject),
				Phlex::SGML::SafeValue.new(%(a"b)),
				Object.new,
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end.merge("fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) })
			end

			def initialize(value)
				@value = value
			end

			def view_template
				div(title: @value) { "a" }
				input(value: @value, disabled: @value == "x", class: "c")
				fragment(:f) { span(title: @value) }
				reassigned = +"old"
				reassigned.define_singleton_method(:include?) { |_| reassigned = "new"; false }
				div(title: reassigned)
			rescue => error
				plain "rescued #{error.class}"
			end
		end
	end
end
