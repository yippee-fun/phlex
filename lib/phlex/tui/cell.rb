# frozen_string_literal: true

class Phlex::TUI::Cell
	attr_accessor :character, :line, :bold, :italic, :underline, :blink, :inverse, :strikethrough, :color, :bg

	def initialize(
		character: nil,
		line: nil,
		bold: nil,
		italic: nil,
		underline: nil,
		blink: nil,
		inverse: nil,
		strikethrough: nil,
		color: nil,
		bg: nil
	)
		@character = character
		@line = line
		@bold = bold
		@italic = italic
		@underline = underline
		@blink = blink
		@inverse = inverse
		@strikethrough = strikethrough
		@color = color
		@bg = bg
	end
end
