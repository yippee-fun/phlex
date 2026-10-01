# frozen_string_literal: true

module EquivalenceCases
	module SameLineDefinitions
		class SameLineDefinitions < Phlex::HTML
			def view_template
				div { part }
			end

			# Both definitions have the same source location, so the compiler
			# can't tell which one is live and must leave them alone.
			unless ENV.key?("PHLEX_NEVER_SET") then def part = span { "live" } else def part = span { "never" } end
		end
	end
end
