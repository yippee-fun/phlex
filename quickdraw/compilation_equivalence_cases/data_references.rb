# frozen_string_literal: true

module EquivalenceCases
	module DataReferences
		# `data` is a URL on `object`, unless it's a Hash of `data-*` attributes.
		class DataReferences < Phlex::HTML
			VALUES = [
				"/files/report.pdf",
				"javascript:alert(1)",
				"&#106;avascript:alert(1)",
				:"javascript:alert(1)",
				["javascript:alert(1)"],
				[],
				{ controller: "x", action: "javascript:y" },
				nil,
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end
			end

			def initialize(value)
				@value = value
			end

			def view_template
				object(data: @value)
				object(data: @value, type: "application/pdf")
				object("data" => @value)
				object(data: "/files/#{@value}")
				object(data: "#{@value}")
				div(data: { controller: @value.to_s })
			end
		end
	end
end
