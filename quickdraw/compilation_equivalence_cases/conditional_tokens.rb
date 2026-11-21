# frozen_string_literal: true

module EquivalenceCases
	module ConditionalTokens
		class ConditionalTokens < Phlex::HTML
			def self.equivalence_scenarios
				{
					"off" => -> (klass) { klass.new(on: false).call },
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
				div(class: ["field", ("field-error" if @on)]) { "a" }
				span(class: ["badge", (@on ? :is_on : :is_off), ("big" unless @on), 1, ["x", nil]])
				span(class: [(nil if @on), (false unless @on)])
				span(class: ['say "hi"', ("on" if @on)], style: ["color: red", ("margin: 0" if @on)])
				span(class: [("a" if check(:a)), ("b" if check(:b))], title: check(:title))
				span(class: ["c", ("d" if @on)], title: toggle)
				span(class: [("a" if @on), ("b" if @on), ("c" if @on), ("d" if @on)])
				span(class: [("ok" if @on), ({ a: 1 } if @on)])
				conditions
			rescue Phlex::ArgumentError, RuntimeError => error
				plain "rescued #{error.class}"
			ensure
				fragment(:log) { plain @log.join(",") }
			end

			# Expressions that mean something else in condition position.
			private def conditions
				div(class: [("in" if 1 in String), ("or" if (false or itself))])
				2.times { div(class: [("flip" if (@on..!@on))]) } # rubocop:disable Lint/FlipFlop
				div(class: [("é" if @on)], id: "x")
				a(href: [(@log ? "/ok" : "\xFF&")])
				div(class: [(Set["set"] if @on)])
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
