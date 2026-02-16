# frozen_string_literal: true

class Phlex::TUI::Cell
	BOLD = 1 << 0
	ITALIC = 1 << 1
	UNDERLINE = 1 << 2
	BLINK = 1 << 3
	INVERSE = 1 << 4
	STRIKETHROUGH = 1 << 5

	attr_accessor :character, :line, :color, :bg, :flags

	def initialize(
		character: nil,
		line: nil,
		flags: 0,
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
		@flags = flags
		self.bold = bold unless bold.nil?
		self.italic = italic unless italic.nil?
		self.underline = underline unless underline.nil?
		self.blink = blink unless blink.nil?
		self.inverse = inverse unless inverse.nil?
		self.strikethrough = strikethrough unless strikethrough.nil?
		@color = color
		@bg = bg
	end

	def bold
		flag?(BOLD)
	end

	def bold=(value)
		set_flag(BOLD, value)
	end

	def italic
		flag?(ITALIC)
	end

	def italic=(value)
		set_flag(ITALIC, value)
	end

	def underline
		flag?(UNDERLINE)
	end

	def underline=(value)
		set_flag(UNDERLINE, value)
	end

	def blink
		flag?(BLINK)
	end

	def blink=(value)
		set_flag(BLINK, value)
	end

	def inverse
		flag?(INVERSE)
	end

	def inverse=(value)
		set_flag(INVERSE, value)
	end

	def strikethrough
		flag?(STRIKETHROUGH)
	end

	def strikethrough=(value)
		set_flag(STRIKETHROUGH, value)
	end

	private def flag?(mask)
		(@flags & mask) != 0
	end

	private def set_flag(mask, value)
		if value
			@flags |= mask
		else
			@flags &= ~mask
		end
	end
end
