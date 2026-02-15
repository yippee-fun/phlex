# frozen_string_literal: true

class Phlex::TUI::Span < Phlex::TUI::Node
	def initialize(content:, parent:, font: nil, color: nil, bg: nil, bold: nil, italic: nil, underline: nil, blink: nil, inverse: nil, strikethrough: nil)
		@parent = parent
		@content = content.to_s
		@font = font
		@color = (nil == color) ? @parent&.color : color
		@bg = (nil == bg) ? @parent&.bg : bg
		@bold = (nil == bold) ? @parent&.bold : bold
		@italic = (nil == italic) ? @parent&.italic : italic
		@underline = (nil == underline) ? @parent&.underline : underline
		@blink = (nil == blink) ? @parent&.blink : blink
		@inverse = (nil == inverse) ? @parent&.inverse : inverse
		@strikethrough = (nil == strikethrough) ? @parent&.strikethrough : strikethrough
		@requested_width = :fit
		@requested_height = :fit

		natural_width = @content.lines.map(&:chomp).map(&:length).max || 0
		natural_height = @content.lines.size
		longest_word = @content.split(/\s+/).map(&:length).max || 0

		initialize_geometry(
			width: natural_width,
			height: natural_height,
			min_width: [longest_word, 5].min,
			min_height: natural_height,
			max_width: natural_width,
			max_height: Float::INFINITY
		)
	end

	attr_reader :content, :font, :color, :bg, :bold, :italic, :underline, :blink, :inverse, :strikethrough, :requested_width, :requested_height

	private

	attr_reader :parent
end
