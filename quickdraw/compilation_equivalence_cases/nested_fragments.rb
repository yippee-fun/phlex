# frozen_string_literal: true

module EquivalenceCases
	module NestedFragments
		class NestedFragments < Phlex::HTML
			def self.equivalence_scenarios
				{
					"outer only" => -> (klass) { klass.new.call(fragments: ["outer"]) },
					"inner only" => -> (klass) { klass.new.call(fragments: ["inner"]) },
					"id and inner" => -> (klass) { klass.new.call(fragments: ["id", "inner"]) },
					"outer and missing" => -> (klass) { klass.new.call(fragments: ["outer", "nonexistent"]) },
					"inner and missing" => -> (klass) { klass.new.call(fragments: ["inner", "nonexistent"]) },
				}
			end

			def view_template
				div { "before" }
				fragment("id") { div { "x" } }
				div { "after" }
				fragment("outer") do
					p { "o1" }
					fragment("inner") { span { "in" } }
					p { "o2" }
				end
				div { "tail" }
			end
		end
	end
end
