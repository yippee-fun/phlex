# frozen_string_literal: true

module EquivalenceCases
	module MethodShapes
		class MethodShapes < Phlex::HTML
			def self.equivalence_scenarios
				{
					"with arguments" => -> (klass) { klass.new("pos", b: "key").call },
					"label called directly" => -> (klass) { klass.new.label },
				}
			end

			def self.foo
				"class method"
			end

			def initialize(a = "def", b: "kw")
				@a = a
				@b = b
			end

			def view_template
				one_liner
				defaults
				defaults("x", k: "y")
				div { self.class.foo }
				div { "#{@a}-#{@b}" }
				div { label }
			end

			def one_liner = div { "x" }

			def defaults(a = "da", k: "dk")
				span { "#{a}-#{k}" }
			end

			def label
				div if false
				"label"
			end
		end
	end
end
