# frozen_string_literal: true

class Phlex::TUI::Style
	attr_reader :color, :bg_color, :bold, :italic, :underline, :blink, :inverse, :strikethrough

	def initialize(color: nil, bg_color: nil, bold: false, italic: false, underline: false, blink: false, inverse: false, strikethrough: false)
		@color = color
		@bg_color = bg_color
		@bold = bold
		@italic = italic
		@underline = underline
		@blink = blink
		@inverse = inverse
		@strikethrough = strikethrough
	end

	def to_ansi
		codes = []
		codes << 1 if bold
		codes << 3 if italic
		codes << 4 if underline
		codes << 5 if blink
		codes << 7 if inverse
		codes << 9 if strikethrough
		codes << color_code(color, foreground: true) if color
		codes << color_code(bg_color, foreground: false) if bg_color

		return "" if codes.empty?

		"\e[#{codes.join(';')}m"
	end

	def reset_ansi
		"\e[0m"
	end

	private def color_code(color, foreground:)
		base = foreground ? 30 : 40

		case color
			when :black then base
			when :red then base + 1
			when :green then base + 2
			when :yellow then base + 3
			when :blue then base + 4
			when :magenta then base + 5
			when :cyan then base + 6
			when :white then base + 7
			when Integer then "#{foreground ? 38 : 48};5;#{color}"
			when Array then "#{foreground ? 38 : 48};2;#{color.join(';')}"
		end
	end
end
