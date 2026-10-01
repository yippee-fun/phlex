# frozen_string_literal: true

module EquivalenceCases
	module UnlessBlockValue
		class UnlessBlockValue < Phlex::HTML
			def initialize(hidden: false)
				@hidden = hidden
			end

			def view_template
				div { span unless @hidden }
				div { span { "a" } unless @hidden }
				div { unless @hidden then span { "b" } else "c" end }
				div { span if @hidden }
			end

			def self.equivalence_scenarios
				{ "hidden" => ->(klass) { klass.new(hidden: true).call } }
			end
		end
	end
end
