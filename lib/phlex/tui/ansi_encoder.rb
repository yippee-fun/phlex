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

		flags, color, bg = unpack_state(state)

		cells.each do |cell|
			next_flags = cell.flags || 0
			next_color = cell.color
			next_bg = cell.bg

			if flags != next_flags || color != next_color || bg != next_bg
				append_sgr(
					buffer,
					flags:, next_flags:,
					color:, next_color:,
					bg:, next_bg:
				)

				flags = next_flags
				color = next_color
				bg = next_bg
			end

			buffer << cell.character
		end

		buffer << RESET if reset && (flags != 0 || color || bg)
		buffer
	end

	def encode_packed_row(row, width:, state: default_state, reset: false)
		buffer = +""
		flags, color, bg = unpack_state(state)
		col = 0
		base = 0

		while col < width
			next_flags = row[base + Phlex::TUI::Canvas::CELL_FLAGS_OFFSET] || 0
			next_color = row[base + Phlex::TUI::Canvas::CELL_COLOR_OFFSET]
			next_bg = row[base + Phlex::TUI::Canvas::CELL_BG_OFFSET]

			if flags != next_flags || color != next_color || bg != next_bg
				append_sgr(
					buffer,
					flags:, next_flags:,
					color:, next_color:,
					bg:, next_bg:
				)

				flags = next_flags
				color = next_color
				bg = next_bg
			end

			buffer << (row[base + Phlex::TUI::Canvas::CELL_CHARACTER_OFFSET] || " ")
			col += 1
			base += Phlex::TUI::Canvas::CELL_STRIDE
		end

		buffer << RESET if reset && (flags != 0 || color || bg)
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
			[flags_from_state(state), state.color, state.bg]
		else
			[0, nil, nil]
		end
	end

	private def append_sgr(buffer, flags:, next_flags:, color:, next_color:, bg:, next_bg:)
		buffer << SGR_PREFIX
		first = true

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::BOLD)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::BOLD) ? 1 : 22)
		end

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::ITALIC)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::ITALIC) ? 3 : 23)
		end

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::UNDERLINE)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::UNDERLINE) ? 4 : 24)
		end

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::BLINK)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::BLINK) ? 5 : 25)
		end

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::INVERSE)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::INVERSE) ? 7 : 27)
		end

		if flag_changed?(flags, next_flags, Phlex::TUI::Canvas::STRIKETHROUGH)
			first = append_sgr_integer(buffer, first, flag_set?(next_flags, Phlex::TUI::Canvas::STRIKETHROUGH) ? 9 : 29)
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

	private def flags_from_state(state)
		flags = 0
		flags |= Phlex::TUI::Canvas::BOLD if state.bold
		flags |= Phlex::TUI::Canvas::ITALIC if state.italic
		flags |= Phlex::TUI::Canvas::UNDERLINE if state.underline
		flags |= Phlex::TUI::Canvas::BLINK if state.blink
		flags |= Phlex::TUI::Canvas::INVERSE if state.inverse
		flags |= Phlex::TUI::Canvas::STRIKETHROUGH if state.strikethrough
		flags
	end

	private def flag_set?(flags, mask)
		(flags & mask) != 0
	end

	private def flag_changed?(flags, next_flags, mask)
		((flags ^ next_flags) & mask) != 0
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
