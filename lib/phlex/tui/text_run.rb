# frozen_string_literal: true

class Phlex::TUI::TextRun
	def self.wrap_runs(runs:, width:, mode:, trim_trailing_whitespace: true)
		return [] if width <= 0

		case mode
		in :word
			wrap_word_runs(runs, width, trim_trailing_whitespace:)
		in :grapheme
			wrap_grapheme_runs(runs, width)
		else
			raise ArgumentError, "Unknown wrap mode: #{mode.inspect}"
		end
	end

	def self.wrap_word_runs(runs, width, trim_trailing_whitespace:)
		lines = []
		current_line = []
		current_length = 0
		pending_spaces = []
		pending_word = []

		tokenize_word_runs(runs).each do |token|
			case token[:type]
			in :newline
				current_line, current_length = append_pending_word!(
					lines,
					current_line,
					current_length,
					pending_spaces,
					pending_word,
					width,
					trim_trailing_whitespace:
				)
				pending_spaces.clear
				current_length = trim_line!(current_line, current_length) if trim_trailing_whitespace
				lines << current_line
				current_line = []
				current_length = 0
			in :space
				current_line, current_length = append_pending_word!(
					lines,
					current_line,
					current_length,
					pending_spaces,
					pending_word,
					width,
					trim_trailing_whitespace:
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
			pending_word,
			width,
			trim_trailing_whitespace:
		)
		current_length = trim_line!(current_line, current_length) if trim_trailing_whitespace
		lines << current_line unless current_line.empty?

		lines
	end

	def self.wrap_grapheme_runs(runs, width)
		lines = []
		current_line = []
		current_width = 0

		runs.each do |run|
			Phlex::TUI::TextWidth.each_grapheme(run[:text]) do |grapheme|
				if grapheme == "\n"
					lines << current_line
					current_line = []
					current_width = 0
					next
				end

				grapheme_width = Phlex::TUI::TextWidth.grapheme_width(grapheme)
				if !current_line.empty? && (current_width + grapheme_width) > width
					lines << current_line
					current_line = []
					current_width = 0
				end

				append_grapheme_run!(current_line, run, grapheme)
				current_width += grapheme_width
			end
		end

		lines << current_line unless current_line.empty?
		lines
	end

	def self.append_grapheme_run!(line_runs, run, grapheme)
		if line_runs.empty?
			line_runs << run.merge(text: grapheme)
			return
		end

		last = line_runs.last
		if same_style?(last, run)
			last[:text] << grapheme
		else
			line_runs << run.merge(text: grapheme)
		end
	end

	def self.same_style?(left, right)
		left[:font] == right[:font] &&
			left[:color] == right[:color] &&
			left[:bg] == right[:bg] &&
			left[:bold] == right[:bold] &&
			left[:italic] == right[:italic] &&
			left[:underline] == right[:underline] &&
			left[:blink] == right[:blink] &&
			left[:inverse] == right[:inverse] &&
			left[:strikethrough] == right[:strikethrough]
	end

	def self.trim_line!(line_runs, line_length)
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

	def self.append_pending_word!(lines, current_line, current_length, pending_spaces, pending_word, width, trim_trailing_whitespace:)
		return [current_line, current_length] if pending_word.empty?

		spaces_length = pending_spaces.sum { |run| Phlex::TUI::TextWidth.string_width(run[:text]) }
		word_length = pending_word.sum { |run| Phlex::TUI::TextWidth.string_width(run[:text]) }

		if current_line.empty?
			current_line.concat(pending_word)
			current_length = word_length
		elsif current_length + spaces_length + word_length <= width
			current_line.concat(pending_spaces)
			current_line.concat(pending_word)
			current_length += spaces_length + word_length
		else
			current_length = trim_line!(current_line, current_length) if trim_trailing_whitespace
			lines << current_line
			current_line = pending_word.map(&:dup)
			current_length = word_length
		end

		pending_spaces.clear
		pending_word.clear
		[current_line, current_length]
	end

	def self.tokenize_word_runs(runs)
		tokens = []

		runs.each do |run|
			run[:text].split(/(\n|\s+)/).each do |piece|
				next if piece.empty?

				type = if piece == "\n"
					:newline
				elsif piece.match?(/\A\s+\z/)
					:space
				else
					:word
				end

				tokens << run.merge(type:, text: piece)
			end
		end

		tokens
	end

	def self.token_to_run(token)
		{
			text: token[:text],
			font: token[:font],
			color: token[:color],
			bg: token[:bg],
			bold: token[:bold],
			italic: token[:italic],
			underline: token[:underline],
			blink: token[:blink],
			inverse: token[:inverse],
			strikethrough: token[:strikethrough],
		}
	end
end
