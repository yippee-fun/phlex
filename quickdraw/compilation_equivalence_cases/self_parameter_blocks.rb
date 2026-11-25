# frozen_string_literal: true

module EquivalenceCases
	module SelfParameterBlocks
		class Icon < Phlex::SVG
			def self.equivalence_scenarios
				{
					"off" => -> (klass) { klass.new(on: false).call },
					"fragment" => -> (klass) { klass.new.call(fragments: [:f]) },
					"raising" => -> (klass) { klass.new(raising: true).call },
				}
			end

			def initialize(on: true, raising: false)
				@on = on
				@raising = raising
			end

			def view_template
				svg(viewBox: "0 0 24 24") do |s|
					s.path(d: "M0 0h24v24H0z", stroke: "currentColor")
					s.g(class: ["g", ("on" if @on)]) { |inner| inner.circle(cx: 12, r: label) }
					s.g { s.rect(width: @on) }
					fragment(:f) { s.line(x1: 1) }
					s.text { "label" }
					raise "raising" if @raising
				end

				svg { |s| s.path(d: "a") if @on }
				svg { |s| label(s) }
				svg { |s| s = self; s.path(d: "b") }
				svg { |s| s&.path(d: "c") }
				svg { |s, t| s.path(d: t.inspect) }
				svg { |s| [1].each { |s| s.to_s }; s.path(d: "d") }
				svg { |s| next if @on; s.path(d: "e") }
				svg { |s| s.path(d: binding.local_variable_defined?(:s).to_s) }
				defs = "local"
				svg { |s| s.defs; s.path(d: defs) }
				svg { |s| s.secret }
				svg { |s| Rebinder.new.instance_exec { s.path(d: "f") } }
				svg { |s| -> { s.path(d: "g") }.call }
				svg { |s| ::Kernel.eval("s").path(d: "h") }
				svg { |s| s.path(d: Kernel.binding.local_variable_defined?(:s).to_s) }
			rescue RuntimeError => error
				plain "rescued #{error.message}"
			end

			private def label(component = nil) = component ? component.class.name : "12"

			def secret
				plain "public"
			end
		end

		class Rebinder
			def path(**) = "rebound"
		end

		class PrivateElement < Phlex::SVG
			def view_template
				svg { |s| s.path(d: "a") }
			rescue NoMethodError => error
				plain "rescued #{error.name}"
			end

			private def path(...) = super
		end

		class Page < Phlex::HTML
			def initialize(on: true) = @on = on

			def view_template
				div(class: "a") { |d| d.span { "x" }; d.br; plain "y" }
				ul { |list| [1, 2].each { |i| list.li { i } } }
				div { |d| d.span(class: [("on" if @on)]) { @on.inspect } }
			end
		end
	end
end
