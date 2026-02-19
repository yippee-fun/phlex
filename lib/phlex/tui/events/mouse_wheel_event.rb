# frozen_string_literal: true

class Phlex::TUI::MouseWheelEvent < Phlex::TUI::MouseEvent
	def initialize(delta_y:, col:, row:, button:, shift:, alt:, ctrl:, raw:, timestamp: nil)
		super(col:, row:, button:, shift:, alt:, ctrl:, raw:, timestamp:)
		@delta_y = delta_y
	end

	attr_reader :delta_y

	def with_delta(delta_y)
		self.class.new(
			delta_y:,
			col: @col,
			row: @row,
			button: @button,
			shift: @shift,
			alt: @alt,
			ctrl: @ctrl,
			raw: @raw
		)
	end
end
