# frozen_string_literal: true

module EquivalenceCases
	module EmptyKeywordSplat
		class EmptyKeywordSplat < Phlex::HTML
			def self.equivalence_scenarios = { "with attributes" => -> (klass) { klass.new(id: "a").call } }

			def initialize(**attrs)
				@attrs = attrs
			end

			def view_template
				div(**@attrs) { "x" }
				div(**{}) { "empty" }
			end
		end
	end
end
