# frozen_string_literal: true

class Phlex::TUI::Span < Phlex::TUI::Node
	def initialize(content:, parent:, font: nil, color: nil, bg: nil, bold: nil, italic: nil, underline: nil, blink: nil, inverse: nil, strikethrough: nil)
		@parent = parent
		@content = normalize_utf8(content.to_s)
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

		natural_width = @content.lines.map(&:chomp).map { |line| Phlex::TUI::TextWidth.string_width(line) }.max || 0
		natural_height = @content.lines.size
		longest_word = @content.split(/\s+/).map { |word| Phlex::TUI::TextWidth.string_width(word) }.max || 0

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

	def normalize_utf8(text)
		value = text.dup
		value = value.force_encoding(Encoding::UTF_8) unless value.encoding == Encoding::UTF_8
		return value if value.valid_encoding?

		value.scrub
	end

	attr_reader :parent
end
