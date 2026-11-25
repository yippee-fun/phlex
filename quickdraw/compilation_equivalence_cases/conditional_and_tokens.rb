# frozen_string_literal: true

module EquivalenceCases
	module ConditionalAndTokens
		class ConditionalAndTokens < Phlex::HTML
			def self.equivalence_scenarios
				{
					"off" => -> (klass) { klass.new(on: false).call },
					"nil" => -> (klass) { klass.new(on: nil).call },
					"truthy object" => -> (klass) { klass.new(on: Object.new).call },
					"fragment" => -> (klass) { klass.new.call(fragments: [:log]) },
					"raising" => -> (klass) { klass.new(raising: true).call },
				}
			end

			def initialize(on: true, raising: false)
				@on = on
				@raising = raising
				@log = []
			end

			def view_template
				div(class: ["field", (@on && "field-error")]) { "a" }
				span(class: ["badge", @on && :is_on, (!@on && "off"), (@on and "and")])
				span(class: [(check(:a) && "a"), (check(:b) && "b")], title: check(:title))
				span(class: ["c", (@on && "d")], title: toggle)
				span(class: [((@on || @raising) && "either"), (@on && ["x", nil]), (@on && nil)])
				span(class: [(@log.empty? && "empty"), (self.class::ON && "constant")])
				span(class: [(@on && "a"), (@on && "b"), (@on && "c"), (@on && "d")])
				span(class: [(@on && { a: 1 })])
				conditions
			rescue Phlex::ArgumentError, RuntimeError => error
				plain "rescued #{error.class}"
			ensure
				fragment(:log) { plain @log.join(",") }
			end

			ON = true

			# Expressions that mean something else in condition position stay as they are.
			private def conditions
				div(class: [(/x/ && "regexp"), (1 && "literal")])
				2.times { div(class: [((@on..!@on) && "range")]) }
				div(class: [(@on && "é")], id: "x")
			end

			private def check(name)
				@log << name
				raise "check" if @raising && name == :b

				@on
			end

			private def toggle
				@on = !@on
				"toggled"
			end
		end
	end
end
