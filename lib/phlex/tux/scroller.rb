# frozen_string_literal: true

class Tux::Scroller < Phlex::TUI
	def initialize(**attributes)
		@scroll_position = 0
		@attributes = attributes
	end

	def view_template(&)
		box(**@attributes) do
			hstack(width: :grow, height: :grow) do
				box(width: :grow, height: :grow, padding: { top: @scroll_position }, &)
				box(width: 1, height: :grow) do
					# Scrollbar here
				end
			end
		end
	end

	def scroll_down(amount = 1)
		@scroll_position -= amount
	end

	def scroll_up(amount = 1)
		@scroll_position += amount
	end
end
