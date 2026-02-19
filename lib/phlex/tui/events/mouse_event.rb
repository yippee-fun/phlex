# frozen_string_literal: true

class Phlex::TUI::MouseEvent < Phlex::TUI::Event
	def initialize(col:, row:, button:, shift:, alt:, ctrl:, raw:, timestamp: nil)
		super(timestamp:)
		@col = col
		@row = row
		@button = button
		@shift = shift
		@alt = alt
		@ctrl = ctrl
		@raw = raw
	end

	attr_reader :col
	attr_reader :row
	attr_reader :button
	attr_reader :shift
	attr_reader :alt
	attr_reader :ctrl
	attr_reader :raw
end
