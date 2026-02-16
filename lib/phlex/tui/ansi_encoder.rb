# frozen_string_literal: true

class Phlex::TUI::AnsiEncoder
	RESET = "\e[0m"
	SGR_SEPARATOR = ";"
	SGR_PREFIX = "\e["
	SGR_SUFFIX = "m"

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

		bold, italic, underline, blink, inverse, strikethrough, color, bg = unpack_state(state)

		cells.each do |cell|
			next_bold = !!cell.bold
			next_italic = !!cell.italic
			next_underline = !!cell.underline
			next_blink = !!cell.blink
			next_inverse = !!cell.inverse
			next_strikethrough = !!cell.strikethrough
			next_color = cell.color
			next_bg = cell.bg

			if bold != next_bold || italic != next_italic || underline != next_underline || blink != next_blink || inverse != next_inverse || strikethrough != next_strikethrough || color != next_color || bg != next_bg
				append_sgr(
					buffer,
					bold:, next_bold:,
					italic:, next_italic:,
					underline:, next_underline:,
					blink:, next_blink:,
					inverse:, next_inverse:,
					strikethrough:, next_strikethrough:,
					color:, next_color:,
					bg:, next_bg:
				)

				bold = next_bold
				italic = next_italic
				underline = next_underline
				blink = next_blink
				inverse = next_inverse
				strikethrough = next_strikethrough
				color = next_color
				bg = next_bg
			end

			buffer << cell.character
		end

		buffer << RESET if reset && (bold || italic || underline || blink || inverse || strikethrough || color || bg)
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

	private def unpack_state(state)
		if State === state
			[
				!!state.bold,
				!!state.italic,
				!!state.underline,
				!!state.blink,
				!!state.inverse,
				!!state.strikethrough,
				state.color,
				state.bg,
			]
		else
			[false, false, false, false, false, false, nil, nil]
		end
	end

	private def append_sgr(buffer, bold:, next_bold:, italic:, next_italic:, underline:, next_underline:, blink:, next_blink:, inverse:, next_inverse:, strikethrough:, next_strikethrough:, color:, next_color:, bg:, next_bg:)
		buffer << SGR_PREFIX
		first = true

		if bold != next_bold
			first = append_sgr_integer(buffer, first, next_bold ? 1 : 22)
		end

		if italic != next_italic
			first = append_sgr_integer(buffer, first, next_italic ? 3 : 23)
		end

		if underline != next_underline
			first = append_sgr_integer(buffer, first, next_underline ? 4 : 24)
		end

		if blink != next_blink
			first = append_sgr_integer(buffer, first, next_blink ? 5 : 25)
		end

		if inverse != next_inverse
			first = append_sgr_integer(buffer, first, next_inverse ? 7 : 27)
		end

		if strikethrough != next_strikethrough
			first = append_sgr_integer(buffer, first, next_strikethrough ? 9 : 29)
		end

		if color != next_color
			if next_color
				first = append_sgr_color(buffer, first, next_color, foreground: true)
			else
				first = append_sgr_integer(buffer, first, 39)
			end
		end

		if bg != next_bg
			if next_bg
				first = append_sgr_color(buffer, first, next_bg, foreground: false)
			else
				first = append_sgr_integer(buffer, first, 49)
			end
		end

		buffer << SGR_SUFFIX
	end

	private def append_sgr_color(buffer, first, color, foreground:)
		code = foreground ? 38 : 48
		r, g, b = color

		if @truecolor
			first = append_sgr_integer(buffer, first, code)
			first = append_sgr_integer(buffer, first, 2)
			first = append_sgr_integer(buffer, first, r)
			first = append_sgr_integer(buffer, first, g)
			append_sgr_integer(buffer, first, b)
		else
			first = append_sgr_integer(buffer, first, code)
			first = append_sgr_integer(buffer, first, 5)
			append_sgr_integer(buffer, first, rgb_to_ansi256(r, g, b))
		end
	end

	private def append_sgr_integer(buffer, first, value)
		buffer << SGR_SEPARATOR unless first
		buffer << value.to_s
		false
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
