# frozen_string_literal: true

module EquivalenceCases
	module FragmentBlockPass
		class FragmentBlockPass < Phlex::HTML
			def self.equivalence_scenarios = { "a only" => -> (klass) { klass.new.call(fragments: [:a]) } }

			def view_template
				div { "before" }
				fragment(:a, &proc { div })
				div { "after" }
			end
		end
	end
end
