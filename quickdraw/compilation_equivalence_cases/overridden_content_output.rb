# frozen_string_literal: true

module EquivalenceCases
	module OverriddenContentOutput
		class OverriddenContentOutput < Phlex::HTML
			VALUES = [
				"text <b>",
				:a_symbol,
				1,
				1.5,
				nil,
				Object.new,
				Phlex::SGML::SafeValue.new("<i>"),
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
				value = @value
				div { @value }
				div { value }
				div { @value || value }
				div { content }
				div { |component| component.content } # rubocop:disable Style/SymbolProc
				div { next @value }
				[1].each { div { break } }
				whitespace { @value }
				comment
				fragment(:f) { span { @value } }
			end

			def content = @value

			private def __implicit_output__(_content) = plain("implicit")

			private def __yield_content__ = plain("yielded")

			private def format_object(object)
				(Float === object) ? "float #{object}" : super
			end
		end
	end
end
