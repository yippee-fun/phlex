# frozen_string_literal: true

module EquivalenceCases
	module ExpectedLocals
		class Literals < Phlex::HTML
			def self.equivalence_scenarios = { "fragment" => -> (klass) { klass.new.call(fragments: [:f]) } }

			def view_template
				count = 1
				label = "<b>&"
				kind = :a_b
				ratio = 1e3
				none = nil
				yes = true
				no = false
				span { "before" }
				div { count }
				div { label }
				div { kind }
				div { ratio }
				div { none }
				div { yes }
				div { no }
				div { span { label } }
				fragment(:f) { p { count } }
				plain label
				plain count
				plain 1.5
				plain none
				span { "after" }
			end
		end

		class ChangedThroughBinding < Phlex::HTML
			def view_template
				count = 1
				label = "a"
				binding.local_variable_set(:count, 2)
				rebind { nil }
				div { count }
				div { label }
			end

			def rebind(&block) = block.binding.local_variable_set(:label, :rebound)
		end

		class ChangedByTrace < Phlex::HTML
			def view_template
				label = "a"
				trace = TracePoint.new(:line) { |point| point.binding.local_variable_set(:label, "traced") if point.binding.local_variable_defined?(:label) }
				trace.enable { nil }
				div { label }
			end
		end

		class Unassigned < Phlex::HTML
			def view_template
				count = 1 if @never
				div { count }
			end
		end

		class Shadowed < Phlex::HTML
			def view_template
				label = "outer"
				["inner"].each { |label| div { label } } # rubocop:disable Lint/ShadowingOuterLocalVariable
				div { label }
			end
		end

		class Reassigned < Phlex::HTML
			def view_template
				label = "a"
				-> { label = "b" }.call
				count = 1
				count += 1
				div { label }
				div { count }
			end
		end

		class PlainBoolean < Phlex::HTML
			def view_template
				yes = true
				plain yes
			rescue Phlex::ArgumentError
				plain "rescued"
			end
		end

		class InsideGuardedBlock < Phlex::HTML
			def view_template
				label = "a"
				wrap { div { label } }
			end

			def wrap = yield
		end

		class FormattedNumbers < Phlex::HTML
			def view_template
				count = 1
				label = "a"
				div { count }
				div { label }
				div { 2 }
				plain count
				plain 3
			end

			private def format_object(object) = "number #{object}"
		end
	end
end
