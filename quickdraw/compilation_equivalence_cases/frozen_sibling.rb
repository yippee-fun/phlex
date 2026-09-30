# frozen_string_literal: true

module EquivalenceCases
	module FrozenSibling
		class Frozen < Phlex::HTML
			def view_template = div { "frozen" }
		end

		Frozen.freeze

		class Sibling < Phlex::HTML
			def view_template = div { "sibling" }
		end
	end
end
