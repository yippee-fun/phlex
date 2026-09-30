# frozen_string_literal: true

module EquivalenceCases
	module Namespaces
		module Outer
			module Inner
				class Component < Phlex::HTML
					def self.equivalence_scenarios = { "not phlex" => -> (_klass) { NotPhlex.new.view_template } }

					def view_template
						div { "nested" }
						part
					end

					def part
						span { "part" }
					end
				end
			end

			class Overriding < Inner::Component
				def part
					b { "overridden" }
				end
			end
		end

		class Outer::Inner::Component
			def reopened
				i { "reopened" }
			end

			def view_template # rubocop:disable Lint/DuplicateMethods
				div { "nested2" }
				part
				reopened
			end
		end

		class NotPhlex
			def div = "not phlex div"
			def view_template = div
		end

		class Outer::Sub < Outer::Inner::Component
			def view_template
				super
				em { "sub" }
			end
		end
	end
end
