# frozen_string_literal: true

class Phlex::TUI::MouseUpEvent < Phlex::TUI::MouseEvent
	def initialize(col:, row:, button:, shift:, alt:, ctrl:, raw:, timestamp: nil)
		super
	end
end
