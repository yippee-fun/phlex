# frozen_string_literal: true

class Phlex::TUI::AnsiEncoder
	RESET = "\e[0m"

	State = Data.define(
		:bold,
		:italic,
		:underline,
		:blink,
		:inverse,
		:strikethrough,
		:color,
		:bg,
	)

	def initialize(truecolor: Phlex::TUI::Terminal.truecolor?)
		@truecolor = truecolor
	end

	def encode_cells(cells, state: default_state, reset: false)
		buffer = +""
		state = render_cells(cells, buffer, state)
		buffer << RESET if reset && state != default_state
		buffer
	end

	def default_state
		State.new(
			bold: false,
			italic: false,
			underline: false,
			blink: false,
			inverse: false,
			strikethrough: false,
			color: nil,
			bg: nil,
		)
	end

	private def next_state(cell)
		State.new(
			bold: !!cell.bold,
			italic: !!cell.italic,
			underline: !!cell.underline,
			blink: !!cell.blink,
			inverse: !!cell.inverse,
			strikethrough: !!cell.strikethrough,
			color: cell.color,
			bg: cell.bg,
		)
	end

	private def sgr_codes(previous, cell)
		next_style = next_state(cell)
		return [] if previous == next_style

		codes = []

		if previous.bold != next_style.bold
			codes << (next_style.bold ? 1 : 22)
		end

		if previous.italic != next_style.italic
			codes << (next_style.italic ? 3 : 23)
		end

		if previous.underline != next_style.underline
			codes << (next_style.underline ? 4 : 24)
		end

		if previous.blink != next_style.blink
			codes << (next_style.blink ? 5 : 25)
		end

		if previous.inverse != next_style.inverse
			codes << (next_style.inverse ? 7 : 27)
		end

		if previous.strikethrough != next_style.strikethrough
			codes << (next_style.strikethrough ? 9 : 29)
		end

		if previous.color != next_style.color
			if next_style.color
				codes.concat(ansi_color(next_style.color, foreground: true))
			else
				codes << 39
			end
		end

		if previous.bg != next_style.bg
			if next_style.bg
				codes.concat(ansi_color(next_style.bg, foreground: false))
			else
				codes << 49
			end
		end

		codes
	end

	private def render_cells(cells, buffer, state)
		cells.each do |cell|
			codes = sgr_codes(state, cell)
			buffer << "\e[#{codes.join(';')}m" if codes.any?
			buffer << cell.character
			state = next_state(cell)
		end

		state
	end

	private def ansi_color(color, foreground:)
		code = foreground ? 38 : 48
		r, g, b = color

		if @truecolor
			[code, 2, r, g, b]
		else
			[code, 5, rgb_to_ansi256(r, g, b)]
		end
	end

	private def rgb_to_ansi256(r, g, b)
		r = r.clamp(0, 255)
		g = g.clamp(0, 255)
		b = b.clamp(0, 255)

		if r == g && g == b
			return 16 if r < 8
			return 231 if r > 248
			return (((r - 8) / 10.67).round + 232).clamp(232, 255)
		end

		to_cube = -> (v) { ((v / 255.0) * 5).round.clamp(0, 5) }
		16 + (36 * to_cube.call(r)) + (6 * to_cube.call(g)) + to_cube.call(b)
	end
end
