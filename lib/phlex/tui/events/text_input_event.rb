# frozen_string_literal: true

class Phlex::TUI::TextInputEvent < Phlex::TUI::Event
	def initialize(text:, raw: nil, timestamp: nil)
		super(timestamp:)
		@text = text
		@raw = raw || text
	end

	attr_reader :text
	attr_reader :raw
end
