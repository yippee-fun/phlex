# frozen_string_literal: true

module EquivalenceCases
	module NestedAttributeHashes
		class Loud
			def initialize(log, name) = (@log = log; @name = name)

			def to_h
				@log << @name
				raise "loud" if @name == :raise

				{ name: @name }
			end
		end

		class NestedAttributeHashes < Phlex::HTML
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
				{ deeper: "x", _: true },
				"x".encode(Encoding::UTF_16LE),
				Phlex::SGML::SafeValue.new(%(a"b)),
				Object.new,
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end.merge(
					"fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) },
					"raising" => -> (klass) { klass.new(:raise).call },
				)
			end

			def initialize(value)
				@value = value
				@log = []
			end

			def view_template
				div(data: { controller: "c", value: @value, other_value: "o" }) { "a" }
				input(aria: { label: @value, hidden: @value }, class: "c")
				div(data: { "string-key" => @value, :_ => @value })
				div(style: { color: @value })
				div(data: { "\xFF" => @missing, :ok => @value })
				div(data: { a: Loud.new(@log, :first), b: Loud.new(@log, @value) }, id: next_id)
				fragment(:f) { span(data: { v: @value }) }
				plain @log.join(",")
				div(http: { equiv: @value })
			rescue => error
				plain "rescued #{error.class} #{@log.join(',')}"
			end

			private def next_id
				@log << :id
				"id"
			end
		end
	end
end
