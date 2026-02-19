# frozen_string_literal: true

class Phlex::TUI::Paragraph < Phlex::TUI::Node
	def initialize(parent:, color: nil, bg: nil, bold: nil, italic: nil, underline: nil, blink: nil, inverse: nil, strikethrough: nil, trim_trailing_whitespace: true)
		@parent = parent
		@children = []
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
		@wrapped_lines = []
		@trim_trailing_whitespace = trim_trailing_whitespace

		initialize_geometry(
			width: 0,
			height: 0,
			min_width: 0,
			min_height: 0,
			max_width: 0,
			max_height: Float::INFINITY
		)
	end

	attr_reader :children, :color, :bg, :bold, :italic, :underline, :blink, :inverse, :strikethrough, :requested_width, :requested_height

	def fit_width(_renderer)
		validate_structure!

		content = plain_content
		natural_width = content.lines.map(&:chomp).map { |line| Phlex::TUI::TextWidth.string_width(line) }.max || 0
		longest_word = content.split(/\s+/).map { |word| Phlex::TUI::TextWidth.string_width(word) }.max || 0
		available_parent_width = if parent
			[parent.width - parent.inset_horizontal, 0].max
		else
			0
		end

		effective_width = if parent && parent.text_align != :left
			[natural_width, available_parent_width].max
		else
			natural_width
		end

		self.width = effective_width
		self.min_width = [min_width, [longest_word, 5].min].max
		self.max_width = [max_width, effective_width].max
	end

	def wrap_text(_renderer)
		return if width <= 0

		mode = @trim_trailing_whitespace ? :word : :grapheme
		@wrapped_lines = Phlex::TUI::TextRun.wrap_runs(
			runs: styled_runs,
			width:,
			mode:,
			trim_trailing_whitespace: @trim_trailing_whitespace
		)
		self.height = @wrapped_lines.size
		self.min_height = @wrapped_lines.size
	end

	def draw(renderer)
		render_width = drawing_width
		return if render_width <= 0

		render_col = drawing_col

		@wrapped_lines.each_with_index do |line_runs, index|
			clipped_runs = clip_runs(line_runs, render_width)
			visible_length = clipped_runs.sum { |run| Phlex::TUI::TextWidth.string_width(run[:text]) }
			effective_align = parent&.text_align || :left
			offset = case effective_align
				when :left then 0
				when :right then [render_width - visible_length, 0].max
				when :center then [(render_width - visible_length) / 2, 0].max
				else 0
			end

			cursor = 0
			clipped_runs.each do |run|
				renderer.canvas.paint_text(
					row: row + index,
					col: render_col + offset + cursor,
					text: run[:text],
					font: run[:font],
					color: run[:color],
					bg: run[:bg],
					bold: run[:bold],
					italic: run[:italic],
					underline: run[:underline],
					blink: run[:blink],
					inverse: run[:inverse],
					strikethrough: run[:strikethrough]
				)
				cursor += Phlex::TUI::TextWidth.string_width(run[:text])
			end
		end
	end

	private def drawing_col
		if parent
			parent.col + parent.border_left_width + parent.padding.left
		else
			col
		end
	end

	private def drawing_width
		if parent
			[parent.width - parent.inset_horizontal, 0].max
		else
			width
		end
	end

	private def plain_content
		children.map(&:content).join
	end

	private def validate_structure!
		children.each do |child|
			next if Phlex::TUI::Span === child

			raise ArgumentError, "Paragraphs can only contain spans"
		end
	end

	private def clip_runs(runs, max_length)
		remaining = max_length
		clipped = []

		runs.each do |run|
			break if remaining <= 0

			text = Phlex::TUI::TextWidth.take_by_width(run[:text], remaining)
			next if text.empty?

			clipped << {
				text:,
				font: run[:font],
				color: run[:color],
				bg: run[:bg],
				bold: run[:bold],
				italic: run[:italic],
				underline: run[:underline],
				blink: run[:blink],
				inverse: run[:inverse],
				strikethrough: run[:strikethrough],
			}

			remaining -= Phlex::TUI::TextWidth.string_width(text)
		end

		clipped
	end

	private def styled_runs
		runs = []
		children.each do |span|
			runs << {
				text: span.content,
				font: span.font,
				color: span.color,
				bg: span.bg,
				bold: span.bold,
				italic: span.italic,
				underline: span.underline,
				blink: span.blink,
				inverse: span.inverse,
				strikethrough: span.strikethrough,
			}
		end

		runs
	end

	private

	attr_reader :parent
end
