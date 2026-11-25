# frozen_string_literal: true

module EquivalenceCases
	module KitCallsRefined
		module Components
			extend Phlex::Kit

			class Card < Phlex::HTML
				def initialize(title) = @title = title
				def view_template = plain(@title)
			end
		end

		module Refined
			refine Components::Card.singleton_class do
				def new(*) = super("refined")
			end
		end
	end
end

using EquivalenceCases::KitCallsRefined::Refined

module EquivalenceCases
	module KitCallsRefined
		class KitCallsRefined < Phlex::HTML
			include Components

			def view_template
				Card("plain")
				p { "compiled" }
			end
		end
	end
end
