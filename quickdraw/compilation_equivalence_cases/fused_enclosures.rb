# frozen_string_literal: true

module EquivalenceCases
	module FusedEnclosures
		class Loud < String
			def to_str = raise("loud")
		end

		class FusedEnclosures < Phlex::HTML
			register_element :snow, tag: "雪"

			VALUES = [
				"plain <b>",
				:a_symbol,
				1,
				nil,
				Object.new,
				Loud.new("loud"),
				"safe".dup.extend(Phlex::SGML::SafeObject),
				Phlex::SGML::SafeValue.new("<i>"),
				"é".encode(Encoding::ISO_8859_1),
				"x".encode(Encoding::UTF_16LE),
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end.merge(
					"after binary" => -> (klass) { klass.new("é", binary: true).call },
					"fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) },
				)
			end

			def initialize(value, binary: false)
				@value = value
				@binary = binary
			end

			def view_template
				raw safe("\xFF".b) if @binary
				div(class: "card") { div(class: "header") { h3 { @value } }; p { "after" } }
				section { snow { span { @value } } }
				catch(:out) { div { article { throw :out } } }
				ul { [1, 2].each { |i| li { em { break if i == 2 } } } }
				fragment(:f) { aside { nav { @value } } }
			rescue => error
				plain "rescued #{error.class}"
			end
		end
	end
end
