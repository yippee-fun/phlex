# frozen_string_literal: true

class Phlex::TUI::Paragraph < Phlex::TUI::Node
	def initialize(parent:, bold: nil, italic: nil, underline: nil, blink: nil, inverse: nil, strikethrough: nil)
		@parent = parent
		@children = []
		@bold = (nil == bold) ? @parent&.bold : bold
		@italic = (nil == italic) ? @parent&.italic : italic
		@underline = (nil == underline) ? @parent&.underline : underline
		@blink = (nil == blink) ? @parent&.blink : blink
		@inverse = (nil == inverse) ? @parent&.inverse : inverse
		@strikethrough = (nil == strikethrough) ? @parent&.strikethrough : strikethrough
		@requested_width = :fit
		@requested_height = :fit
		@wrapped_lines = []

		initialize_geometry(
			width: 0,
			height: 0,
			min_width: 0,
			min_height: 0,
			max_width: 0,
			max_height: Float::INFINITY
		)
	end

	attr_reader :children, :bold, :italic, :underline, :blink, :inverse, :strikethrough, :requested_width, :requested_height

	def fit_width(_renderer)
		validate_structure!

		content = plain_content
		natural_width = content.lines.map(&:chomp).map(&:length).max || 0
		longest_word = content.split(/\s+/).map(&:length).max || 0
		natural_height = content.lines.size
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
		self.height = natural_height
		self.min_height = [min_height, natural_height].max
	end

	def wrap_text(_renderer)
		return if width <= 0

		lines = []
		current_line = []
		current_length = 0
		pending_spaces = []
		pending_word = []

		tokenize.each do |token|
			case token[:type]
			in :newline
				current_line, current_length = append_pending_word!(
					lines,
					current_line,
					current_length,
					pending_spaces,
					pending_word
				)
				pending_spaces.clear
				current_length = trim_trailing_whitespace!(current_line, current_length)
				lines << current_line
				current_line = []
				current_length = 0
			in :space
				current_line, current_length = append_pending_word!(
					lines,
					current_line,
					current_length,
					pending_spaces,
					pending_word
				)
				pending_spaces << token_to_run(token)
			in :word
				pending_word << token_to_run(token)
			end
		end

		current_line, current_length = append_pending_word!(
			lines,
			current_line,
			current_length,
			pending_spaces,
			pending_word
		)
		current_length = trim_trailing_whitespace!(current_line, current_length)
		lines << current_line unless current_line.empty?

		@wrapped_lines = lines
		self.height = lines.size
		self.min_height = lines.size
	end

	def draw(renderer)
		render_width = drawing_width
		return if render_width <= 0

		render_col = drawing_col

		@wrapped_lines.each_with_index do |line_runs, index|
			clipped_runs = clip_runs(line_runs, render_width)
			visible_length = clipped_runs.sum { |run| run[:text].length }
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
					bold: run[:bold],
					italic: run[:italic],
					underline: run[:underline],
					blink: run[:blink],
					inverse: run[:inverse],
					strikethrough: run[:strikethrough]
				)
				cursor += run[:text].length
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

	private def trim_trailing_whitespace!(line_runs, line_length)
		while (last = line_runs.last)
			stripped = last[:text].sub(/\s+\z/, "")
			break if stripped == last[:text]

			line_length -= (last[:text].length - stripped.length)

			if stripped.empty?
				line_runs.pop
			else
				last[:text] = stripped
				break
			end
		end

		line_length
	end

	private def append_pending_word!(lines, current_line, current_length, pending_spaces, pending_word)
		return [current_line, current_length] if pending_word.empty?

		spaces_length = pending_spaces.sum { |run| run[:text].length }
		word_length = pending_word.sum { |run| run[:text].length }

		if current_line.empty?
			current_line.concat(pending_word)
			current_length = word_length
		elsif current_length + spaces_length + word_length <= width
			current_line.concat(pending_spaces)
			current_line.concat(pending_word)
			current_length += spaces_length + word_length
		else
			current_length = trim_trailing_whitespace!(current_line, current_length)
			lines << current_line
			current_line = pending_word.map(&:dup)
			current_length = word_length
		end

		pending_spaces.clear
		pending_word.clear
		[current_line, current_length]
	end

	private def tokenize
		tokens = []

		children.each do |span|
			span.content.split(/(\n|\s+)/).each do |piece|
				next if piece.empty?

				type = if piece == "\n"
					:newline
				elsif piece.match?(/\A\s+\z/)
					:space
				else
					:word
				end

				tokens << {
					type:,
					text: piece,
					font: span.font,
					bold: span.bold,
					italic: span.italic,
					underline: span.underline,
					blink: span.blink,
					inverse: span.inverse,
					strikethrough: span.strikethrough,
				}
			end
		end

		tokens
	end

	private def token_to_run(token)
		{
			text: token[:text],
			font: token[:font],
			bold: token[:bold],
			italic: token[:italic],
			underline: token[:underline],
			blink: token[:blink],
			inverse: token[:inverse],
			strikethrough: token[:strikethrough],
		}
	end

	private def clip_runs(runs, max_length)
		remaining = max_length
		clipped = []

		runs.each do |run|
			break if remaining <= 0

			text = run[:text][0, remaining]
			next if text.empty?

			clipped << {
				text:,
				font: run[:font],
				bold: run[:bold],
				italic: run[:italic],
				underline: run[:underline],
				blink: run[:blink],
				inverse: run[:inverse],
				strikethrough: run[:strikethrough],
			}

			remaining -= text.length
		end

		clipped
	end

	private

	attr_reader :parent
end
