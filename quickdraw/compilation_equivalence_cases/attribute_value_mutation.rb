# frozen_string_literal: true

module EquivalenceCases
	module AttributeValueMutation
		# Serialising this value changes the component's state, which the
		# runtime has already read for the other attributes.
		class Mutating
			def initialize(component) = @component = component

			def to_h
				@component.mutate
				{ a: "1" }
			end
		end

		class AttributeValueMutation < Phlex::HTML
			def initialize
				@title = "before"
				@active = true
			end

			def mutate
				@title = "after"
				@active = false
			end

			def view_template
				div(id: Mutating.new(self), title: @title)
				div(title: @title, id: Mutating.new(self))
				div(id: Mutating.new(self), class: @active ? "on" : "off")
				div(id: Mutating.new(self), class: "x-#{@title}")
				div(id: Mutating.new(self), class: "static")
			end
		end
	end
end
