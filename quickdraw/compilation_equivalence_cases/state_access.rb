# frozen_string_literal: true

module EquivalenceCases
	module StateAccess
		class StateAccess < Phlex::HTML
			def self.equivalence_scenarios = { "with context" => -> (klass) { klass.new.call(context: { k: "ctx" }) } }

			def view_template
				@sidebar = capture { aside { "side" } }
				vanish { div { "gone" } }
				main { raw safe(@sidebar) }
				div { @_state.buffer.bytesize }
				div { context[:k] }
				div { @_state.capturing.inspect }
				flush
				div { "flushed" }
			end
		end
	end
end
