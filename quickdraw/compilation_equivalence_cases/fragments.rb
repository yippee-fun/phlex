# frozen_string_literal: true

module EquivalenceCases
	module Fragments
		class Fragments < Phlex::HTML
			def self.equivalence_scenarios = { "id only" => -> (klass) { klass.new.call(fragments: ["id"]) } }

			def view_template
				div { "before" }
				fragment("id") { div { "x" } }
				div { "after" }
			end
		end

		class InHelper < Phlex::HTML
			def self.equivalence_scenarios = { "id only" => -> (klass) { klass.new.call(fragments: ["id"]) } }

			def view_template
				div { "before" }
				part
				div { "after" }
			end

			def part
				fragment("id") { div { "in helper" } }
			end
		end

		class DynamicContent < Phlex::HTML
			def self.equivalence_scenarios = { "id only" => -> (klass) { klass.new.call(fragments: ["id"]) } }

			def initialize
				@x = "dyn"
			end

			def view_template
				div { @x }
				fragment("id") { div { @x } }
				div { @x }
			end
		end
	end
end
