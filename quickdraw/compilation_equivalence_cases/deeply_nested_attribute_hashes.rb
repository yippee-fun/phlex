# frozen_string_literal: true

module EquivalenceCases
	module DeeplyNestedAttributeHashes
		class Loud
			def initialize(log, name) = (@log = log; @name = name)

			def to_h
				@log << @name
				raise "loud" if @name == :raise

				{ name: @name }
			end
		end

		class DeeplyNestedAttributeHashes < Phlex::HTML
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
				div(data: { controller: "c", card: { id: @value, open: true, label: "l" } }) { "a" }
				div(data: { a: { b: { c: @value, d: "d" } }, e: @value })
				div(aria: { described: { by: @value } }, class: "c")
				div(data: { card: { _: @value, value: @value } })
				div(data: { _: { x: @value } })
				div(data: { card: { style: { color: @value } } })
				div(data: { card: { "\xFF" => @missing, :ok => @value } })
				div(data: { card: { a: @value, "a" => "duplicate name" } })
				div(data: { card: { **{ x: 1 }, y: @value } })
				div(http: { equiv: { x: @value } })
				div(data: { card: { a: Loud.new(@log, :first), b: { c: Loud.new(@log, @value) } }, d: Loud.new(@log, :last) }, id: next_id)
				fragment(:f) { span(data: { v: { w: @value } }) }
				plain @log.join(",")
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
