# frozen_string_literal: true

class Phlex::TUI::Canvas
	CELL_STRIDE = 5
	CELL_CHARACTER_OFFSET = 0
	CELL_LINE_OFFSET = 1
	CELL_FLAGS_OFFSET = 2
	CELL_COLOR_OFFSET = 3
	CELL_BG_OFFSET = 4

	BOLD = Phlex::TUI::Cell::BOLD
	ITALIC = Phlex::TUI::Cell::ITALIC
	UNDERLINE = Phlex::TUI::Cell::UNDERLINE
	BLINK = Phlex::TUI::Cell::BLINK
	INVERSE = Phlex::TUI::Cell::INVERSE
	STRIKETHROUGH = Phlex::TUI::Cell::STRIKETHROUGH

	LINE_STYLE = {
		:thin => 1,
		:thick => 2,
		:double => 3,
		:rounded => 4,
		:transparent => 0,
	}.freeze

	LINE_CHARACTER = {
		[0, 0, 0, 0].freeze => " ",
		[0, 0, 0, 1].freeze => "╴",
		[0, 0, 0, 2].freeze => "╸",
		[0, 0, 1, 0].freeze => "╷",
		[0, 0, 1, 1].freeze => "┐",
		[0, 0, 1, 2].freeze => "┑",
		[0, 0, 1, 3].freeze => "╕",
		[0, 0, 2, 0].freeze => "╻",
		[0, 0, 2, 1].freeze => "┒",
		[0, 0, 2, 2].freeze => "┓",
		[0, 0, 3, 1].freeze => "╖",
		[0, 0, 3, 3].freeze => "╗",
		[0, 0, 4, 4].freeze => "╮",
		[0, 1, 0, 0].freeze => "╶",
		[0, 1, 0, 1].freeze => "─",
		[0, 1, 0, 2].freeze => "╾",
		[0, 1, 1, 0].freeze => "┌",
		[0, 1, 1, 1].freeze => "┬",
		[0, 1, 1, 2].freeze => "┭",
		[0, 1, 2, 0].freeze => "┎",
		[0, 1, 2, 1].freeze => "┰",
		[0, 1, 2, 2].freeze => "┱",
		[0, 1, 3, 0].freeze => "╓",
		[0, 1, 3, 1].freeze => "╥",
		[0, 2, 0, 0].freeze => "╺",
		[0, 2, 0, 1].freeze => "╼",
		[0, 2, 0, 2].freeze => "━",
		[0, 2, 1, 0].freeze => "┍",
		[0, 2, 1, 1].freeze => "┮",
		[0, 2, 1, 2].freeze => "┯",
		[0, 2, 2, 0].freeze => "┏",
		[0, 2, 2, 1].freeze => "┲",
		[0, 2, 2, 2].freeze => "┳",
		[0, 3, 0, 3].freeze => "═",
		[0, 3, 1, 0].freeze => "╒",
		[0, 3, 1, 3].freeze => "╤",
		[0, 3, 3, 0].freeze => "╔",
		[0, 3, 3, 3].freeze => "╦",
		[0, 4, 4, 0].freeze => "╭",
		[1, 0, 0, 0].freeze => "╵",
		[1, 0, 0, 1].freeze => "┘",
		[1, 0, 0, 2].freeze => "┙",
		[1, 0, 0, 3].freeze => "╛",
		[1, 0, 1, 0].freeze => "│",
		[1, 0, 1, 1].freeze => "┤",
		[1, 0, 1, 2].freeze => "┥",
		[1, 0, 1, 3].freeze => "╡",
		[1, 0, 2, 0].freeze => "╽",
		[1, 0, 2, 1].freeze => "┧",
		[1, 0, 2, 2].freeze => "┪",
		[1, 1, 0, 0].freeze => "└",
		[1, 1, 0, 1].freeze => "┴",
		[1, 1, 0, 2].freeze => "┵",
		[1, 1, 1, 0].freeze => "├",
		[1, 1, 1, 1].freeze => "┼",
		[1, 1, 1, 2].freeze => "┽",
		[1, 1, 2, 0].freeze => "┟",
		[1, 1, 2, 1].freeze => "╁",
		[1, 1, 2, 2].freeze => "╅",
		[1, 2, 0, 0].freeze => "┕",
		[1, 2, 0, 1].freeze => "┶",
		[1, 2, 0, 2].freeze => "┷",
		[1, 2, 1, 0].freeze => "┝",
		[1, 2, 1, 1].freeze => "┾",
		[1, 2, 1, 2].freeze => "┿",
		[1, 2, 2, 0].freeze => "┢",
		[1, 2, 2, 1].freeze => "╆",
		[1, 2, 2, 2].freeze => "╈",
		[1, 3, 0, 0].freeze => "╘",
		[1, 3, 0, 3].freeze => "╧",
		[1, 3, 1, 0].freeze => "╞",
		[1, 3, 1, 3].freeze => "╪",
		[2, 0, 0, 0].freeze => "╹",
		[2, 0, 0, 1].freeze => "┚",
		[2, 0, 0, 2].freeze => "┛",
		[2, 0, 1, 0].freeze => "╿",
		[2, 0, 1, 1].freeze => "┦",
		[2, 0, 1, 2].freeze => "┩",
		[2, 0, 2, 0].freeze => "┃",
		[2, 0, 2, 1].freeze => "┨",
		[2, 0, 2, 2].freeze => "┫",
		[2, 1, 0, 1].freeze => "┸",
		[2, 1, 0, 2].freeze => "┹",
		[2, 1, 1, 0].freeze => "┞",
		[2, 1, 1, 1].freeze => "╀",
		[2, 1, 1, 2].freeze => "╃",
		[2, 1, 2, 0].freeze => "┠",
		[2, 1, 2, 1].freeze => "╂",
		[2, 1, 2, 2].freeze => "╉",
		[2, 2, 0, 0].freeze => "┗",
		[2, 2, 0, 1].freeze => "┺",
		[2, 2, 0, 2].freeze => "┻",
		[2, 2, 1, 0].freeze => "┡",
		[2, 2, 1, 1].freeze => "╄",
		[2, 2, 1, 2].freeze => "╇",
		[2, 2, 2, 0].freeze => "┣",
		[2, 2, 2, 1].freeze => "╊",
		[2, 2, 2, 2].freeze => "╋",
		[3, 0, 0, 1].freeze => "╜",
		[3, 0, 0, 3].freeze => "╝",
		[3, 0, 3, 0].freeze => "║",
		[3, 0, 3, 1].freeze => "╢",
		[3, 0, 3, 3].freeze => "╣",
		[3, 1, 0, 0].freeze => "╙",
		[3, 1, 0, 1].freeze => "╨",
		[3, 1, 3, 0].freeze => "╟",
		[3, 1, 3, 1].freeze => "╫",
		[3, 3, 0, 0].freeze => "╚",
		[3, 3, 0, 3].freeze => "╩",
		[3, 3, 3, 0].freeze => "╠",
		[3, 3, 3, 3].freeze => "╬",
		[4, 0, 0, 4].freeze => "╯",
		[4, 4, 0, 0].freeze => "╰",
	}.freeze

	def initialize(width:, height:, fill: " ")
		@width = width
		@height = height
		@clip_stack = [{ top: 0, left: 0, bottom: height, right: width }]

		@cells = Array.new(height) {
			row = Array.new(width * CELL_STRIDE)
			col = 0
			base = 0

			while col < width
				row[base + CELL_CHARACTER_OFFSET] = fill
				row[base + CELL_FLAGS_OFFSET] = 0
				col += 1
				base += CELL_STRIDE
			end

			row
		}
	end

	def with_clip(row:, col:, width:, height:)
		next_clip = intersect_clip(current_clip, {
			top: row,
			left: col,
			bottom: row + height,
			right: col + width,
		})

		@clip_stack << next_clip
		yield
	ensure
		@clip_stack.pop
	end

	def ansi_color(color, foreground:)
		return unless color

		code = foreground ? 38 : 48

		if Integer === color
			return [code, 5, color]
		end

		r, g, b = resolve_rgb(color)
		if truecolor?
			[code, 2, r, g, b]
		else
			[code, 5, rgb_to_ansi256(r, g, b)]
		end
	end

	def bg(color)
		ansi_color(color, foreground: false)
	end

	def color(color)
		ansi_color(color, foreground: true)
	end

	def truecolor?
		Phlex::TUI::Terminal.truecolor?
	end

	def rgb_to_ansi256(r, g, b)
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

	def ansi256_to_rgb(index)
		index = index.clamp(0, 255)

		if index < 16
			terminal_color(Phlex::TUI::Terminal::PALETTE_COLORS.key(index))
		elsif index < 232
			n = index - 16
			r = n / 36
			g = (n % 36) / 6
			b = n % 6
			levels = [0, 95, 135, 175, 215, 255]
			[levels[r], levels[g], levels[b]]
		else
			gray = 8 + ((index - 232) * 10)
			[gray, gray, gray]
		end
	end

	def resolve_rgb(color)
		case color
		in Symbol
			terminal_color(color)
		in Integer
			ansi256_to_rgb(color)
		in Array[Integer, Integer, Integer]
			color
		in Array[Symbol => name, Float | 0 | 1]
			terminal_color(name)
		in Array[Integer => r, Integer => g, Integer => b, Float | 0 | 1]
			[r, g, b]
		else
			raise ArgumentError, "Unsupported color: #{color.inspect}"
		end
	end

	def to_s
		styled_lines.join("\n")
	end

	def lines
		@cells.map do |row|
			line = +""
			col = 0
			base = 0

			while col < @width
				line << (row[base + CELL_CHARACTER_OFFSET] || " ")
				col += 1
				base += CELL_STRIDE
			end

			line
		end
	end

	def styled_lines
		encoder = Phlex::TUI::AnsiEncoder.new

		@cells.map do |row|
			encoder.encode_packed_row(row, width: @width, reset: true)
		end
	end

	def paint_box(row:, col:, width:, height:, border: nil, bg: nil)
		border = Phlex::TUI::Border.parse(border)

		if bg
			paint_box_fill(
				row + border.top_width,
				col + border.left_width,
				width: [width - border.left_width - border.right_width, 0].max,
				height: [height - border.top_width - border.bottom_width, 0].max,
				bg:
			)
		end

		paint_box_border(row, col, width:, height:, border:) unless border.none?
	end

	def paint_box_border(row, col, width:, height:, border:, color: nil)
		return if width <= 0 || height <= 0

		border = Phlex::TUI::Border.parse(border)
		return if border.none?

		top_style = line_style(border.top)
		right_style = line_style(border.right)
		bottom_style = line_style(border.bottom)
		left_style = line_style(border.left)

		top_left = corner_line(horizontal: top_style, vertical: left_style, orientation: :top_left)
		paint_line_cell(row, col, top_left, color:) if top_left

		top_right = corner_line(horizontal: top_style, vertical: right_style, orientation: :top_right)
		paint_line_cell(row, col + width - 1, top_right, color:) if top_right

		bottom_left = corner_line(horizontal: bottom_style, vertical: left_style, orientation: :bottom_left)
		paint_line_cell(row + height - 1, col, bottom_left, color:) if bottom_left

		bottom_right = corner_line(horizontal: bottom_style, vertical: right_style, orientation: :bottom_right)
		paint_line_cell(row + height - 1, col + width - 1, bottom_right, color:) if bottom_right

		paint_horizontal_line(row, col + 1, width: width - 2, line_style: top_style, color:) if top_style > 0 && width > 2
		paint_horizontal_line(row + height - 1, col + 1, width: width - 2, line_style: bottom_style, color:) if bottom_style > 0 && width > 2

		paint_vertical_line(row + 1, col, height: height - 2, line_style: left_style, color:) if left_style > 0 && height > 2
		paint_vertical_line(row + 1, col + width - 1, height: height - 2, line_style: right_style, color:) if right_style > 0 && height > 2
	end

	def paint_box_fill(row, col, width:, height:, bg:)
		fill_alpha = normalize_color(bg).last
		clip = current_clip
		row_index = [row, clip[:top], 0].max
		row_stop = [row + height, clip[:bottom], @height].min
		col_start = [col, clip[:left], 0].max
		col_stop = [col + width, clip[:right], @width].min
		default_bg = terminal_color(:background)
		default_color = terminal_color(:foreground)

		return if row_index >= row_stop || col_start >= col_stop

		while row_index < row_stop
			row_data = @cells[row_index]
			col_index = col_start
			base = col_start * CELL_STRIDE

			while col_index < col_stop
				row_data[base + CELL_CHARACTER_OFFSET] = " " if fill_alpha == 1
				row_data[base + CELL_BG_OFFSET] = blend(row_data[base + CELL_BG_OFFSET] || default_bg, bg)
				if row_data[base + CELL_CHARACTER_OFFSET] != " "
					row_data[base + CELL_COLOR_OFFSET] = blend(row_data[base + CELL_COLOR_OFFSET] || default_color, bg)
				end

				col_index += 1
				base += CELL_STRIDE
			end

			row_index += 1
		end
	end

	def blend(background, foreground)
		background = normalize_color(background)
		foreground = normalize_color(foreground)

		alpha = (Float === foreground.last) ? foreground.last : 1
		return foreground.first(3) if alpha == 1

		br, bg, bb = background
		fr, fg, fb = foreground

		[
			((fr * alpha) + (br * (1.0 - alpha))).round,
			((fg * alpha) + (bg * (1.0 - alpha))).round,
			((fb * alpha) + (bb * (1.0 - alpha))).round,
		]
	end

	def normalize_color(color)
		case color
		in Array[Symbol => name, Float | 0 | 1 => alpha]
			[*terminal_color(name), alpha]
		in Array[Integer, Integer, Integer, Float | 0 | 1]
			color
		else
			[*resolve_rgb(color), 1]
		end
	end

	def terminal_color(color_name)
		Phlex::TUI::Terminal.color(color_name) or raise ArgumentError, "Unknown color name: #{color_name.inspect}"
	end

	def paint_top_left_corner(row, col, line_style, color: nil)
		paint_line_cell(row, col, [0, line_style, line_style, 0], color:)
	end

	def paint_top_right_corner(row, col, line_style, color: nil)
		paint_line_cell(row, col, [0, 0, line_style, line_style], color:)
	end

	def paint_bottom_left_corner(row, col, line_style, color: nil)
		paint_line_cell(row, col, [line_style, line_style, 0, 0], color:)
	end

	def paint_bottom_right_corner(row, col, line_style, color: nil)
		paint_line_cell(row, col, [line_style, 0, 0, line_style], color:)
	end

	def draw_vertical_line(row, col, height:, style: :thin, color: nil)
		line_style = LINE_STYLE.fetch(style)
		paint_vertical_line(row, col, height:, line_style:, color:)
	end

	def draw_horizontal_line(row, col, width:, style: :thin, color: nil)
		line_style = LINE_STYLE.fetch(style)
		paint_horizontal_line(row, col, width:, line_style:, color:)
	end

	def paint_horizontal_line(row, col, width:, line_style:, color: nil)
		line_style = straight_style(line_style)
		line = [0, line_style, 0, line_style]
		stop = col + width

		i = col
		while i < stop
			paint_line_cell(row, i, line, color:)
			i += 1
		end
	end

	def paint_vertical_line(row, col, height:, line_style:, color: nil)
		line_style = straight_style(line_style)
		line = [line_style, 0, line_style, 0]
		stop = row + height

		i = row
		while i < stop
			paint_line_cell(i, col, line, color:)
			i += 1
		end
	end

	def paint_line_cell(row, col, line, color: nil)
		t, r, b, l = line

		if t > 0 && (up = raw_cell_line(row - 1, col))
			new_up = merge_lines(up, [0, 0, t, 0])
			set_line_cell(row - 1, col, new_up, color:, clipped: false) if new_up != up

			line = merge_lines(line, [up[2], 0, 0, 0])
		end

		if r > 0 && (right = raw_cell_line(row, col + 1))
			new_right = merge_lines(right, [0, 0, 0, r])
			set_line_cell(row, col + 1, new_right, color:, clipped: false) if new_right != right

			line = merge_lines(line, [0, right[3], 0, 0])
		end

		if b > 0 && (down = raw_cell_line(row + 1, col))
			new_down = merge_lines(down, [b, 0, 0, 0])
			set_line_cell(row + 1, col, new_down, color:, clipped: false) if new_down != down

			line = merge_lines(line, [0, 0, down[0], 0])
		end

		if l > 0 && (left = raw_cell_line(row, col - 1))
			new_left = merge_lines(left, [0, l, 0, 0])
			set_line_cell(row, col - 1, new_left, color:, clipped: false) if new_left != left

			line = merge_lines(line, [0, 0, 0, left[1]])
		end

		existing = cell_line(row, col)
		line = merge_lines(existing, line) if existing

		set_line_cell(row, col, line, color:)
	end

	def set_line_cell(row, col, line, color: nil, clipped: true)
		return unless in_bounds?(row, col)
		if clipped
			clip = current_clip
			return unless row >= clip[:top] && row < clip[:bottom]
			return unless col >= clip[:left] && col < clip[:right]
		end

		character = LINE_CHARACTER[line]
		return unless character

		base = cell_base(col)
		row_data = @cells[row]

		row_data[base + CELL_LINE_OFFSET] = line
		row_data[base + CELL_CHARACTER_OFFSET] = character
		row_data[base + CELL_COLOR_OFFSET] = resolve_rgb(color) if color
	end

	def line_style(style)
		return 0 if style.nil?

		LINE_STYLE.fetch(style)
	end

	def straight_style(style)
		(style == 4) ? 1 : style
	end

	def corner_line(horizontal:, vertical:, orientation:)
		h = horizontal
		v = vertical

		if h > 0 && v > 0
			case orientation
			in :top_left
				[0, h, v, 0]
			in :top_right
				[0, 0, v, h]
			in :bottom_left
				[v, h, 0, 0]
			in :bottom_right
				[v, 0, 0, h]
			end
		elsif h > 0
			h = straight_style(h)
			[0, h, 0, h]
		elsif v > 0
			v = straight_style(v)
			[v, 0, v, 0]
		end
	end

	def merge_lines(a, b)
		a.map! { |it| (it == 4) ? 1 : it }
		b.map! { |it| (it == 4) ? 1 : it }

		merged = a.zip(b).map(&:max)
		LINE_CHARACTER[merged] ? merged : a
	end

	def raw_row(row)
		@cells[row]
	end

	def cell_character(row, col)
		read_cell_slot(row, col, CELL_CHARACTER_OFFSET)
	end

	def set_cell_character(row, col, character)
		write_cell_slot(row, col, CELL_CHARACTER_OFFSET, character)
	end

	def cell_line(row, col)
		read_cell_slot(row, col, CELL_LINE_OFFSET)
	end

	def set_cell_line(row, col, line)
		write_cell_slot(row, col, CELL_LINE_OFFSET, line)
	end

	def cell_flags(row, col)
		read_cell_slot(row, col, CELL_FLAGS_OFFSET)
	end

	def set_cell_flags(row, col, flags)
		write_cell_slot(row, col, CELL_FLAGS_OFFSET, flags)
	end

	def get_cell_bold(row, col)
		get_cell_flag(row, col, BOLD)
	end

	def set_cell_bold(row, col, value)
		set_cell_flag(row, col, BOLD, value)
	end

	def get_cell_italic(row, col)
		get_cell_flag(row, col, ITALIC)
	end

	def set_cell_italic(row, col, value)
		set_cell_flag(row, col, ITALIC, value)
	end

	def get_cell_underline(row, col)
		get_cell_flag(row, col, UNDERLINE)
	end

	def set_cell_underline(row, col, value)
		set_cell_flag(row, col, UNDERLINE, value)
	end

	def get_cell_blink(row, col)
		get_cell_flag(row, col, BLINK)
	end

	def set_cell_blink(row, col, value)
		set_cell_flag(row, col, BLINK, value)
	end

	def get_cell_inverse(row, col)
		get_cell_flag(row, col, INVERSE)
	end

	def set_cell_inverse(row, col, value)
		set_cell_flag(row, col, INVERSE, value)
	end

	def get_cell_strikethrough(row, col)
		get_cell_flag(row, col, STRIKETHROUGH)
	end

	def set_cell_strikethrough(row, col, value)
		set_cell_flag(row, col, STRIKETHROUGH, value)
	end

	def cell_color(row, col)
		read_cell_slot(row, col, CELL_COLOR_OFFSET)
	end

	def set_cell_color(row, col, color)
		write_cell_slot(row, col, CELL_COLOR_OFFSET, color)
	end

	def cell_bg(row, col)
		read_cell_slot(row, col, CELL_BG_OFFSET)
	end

	def set_cell_bg(row, col, bg)
		write_cell_slot(row, col, CELL_BG_OFFSET, bg)
	end

	private def current_clip
		@clip_stack.last
	end

	private def intersect_clip(a, b)
		top = [a[:top], b[:top]].max
		left = [a[:left], b[:left]].max
		bottom = [a[:bottom], b[:bottom]].min
		right = [a[:right], b[:right]].min

		{
			top:,
			left:,
			bottom: [bottom, top].max,
			right: [right, left].max,
		}
	end

	def paint_text(row:, col:, text:, color: nil, bg: nil, font: nil, bold: false, italic: false, underline: false, blink: false, inverse: false, strikethrough: false)
		if font
			text = text.gsub(/[A-Za-z0-9]/, font)
		end

		return unless row >= 0 && row < @height
		clip = current_clip
		return unless row >= clip[:top] && row < clip[:bottom]

		resolved_color = resolve_rgb(color || :foreground)
		resolved_bg = bg ? resolve_rgb(bg) : nil
		flag_mask = 0
		flag_mask |= BOLD if bold
		flag_mask |= ITALIC if italic
		flag_mask |= UNDERLINE if underline
		flag_mask |= BLINK if blink
		flag_mask |= INVERSE if inverse
		flag_mask |= STRIKETHROUGH if strikethrough
		row_data = @cells[row]

		col_index = col
		left = [clip[:left], 0].max
		right = [clip[:right], @width].min

		Phlex::TUI::TextWidth.each_grapheme(text) do |grapheme|
			grapheme_width = Phlex::TUI::TextWidth.grapheme_width(grapheme)

			if col_index >= left && col_index < right
				next_col = col_index + grapheme_width - 1
				break if next_col >= right || next_col >= @width

				base = cell_base(col_index)
				clear_previous_wide_overlap!(row_data, col_index)
				clear_current_wide_tail!(row_data, col_index)
				row_data[base + CELL_LINE_OFFSET] = nil
				row_data[base + CELL_CHARACTER_OFFSET] = grapheme
				row_data[base + CELL_COLOR_OFFSET] = resolved_color
				row_data[base + CELL_BG_OFFSET] = resolved_bg if resolved_bg
				if flag_mask != 0
					flags = row_data[base + CELL_FLAGS_OFFSET] || 0
					row_data[base + CELL_FLAGS_OFFSET] = flags | flag_mask
				else
					row_data[base + CELL_FLAGS_OFFSET] = 0
				end

				if grapheme_width == 2
					continuation_base = cell_base(col_index + 1)
					row_data[continuation_base + CELL_LINE_OFFSET] = nil
					row_data[continuation_base + CELL_CHARACTER_OFFSET] = nil
					row_data[continuation_base + CELL_COLOR_OFFSET] = resolved_color
					row_data[continuation_base + CELL_BG_OFFSET] = resolved_bg if resolved_bg
					row_data[continuation_base + CELL_FLAGS_OFFSET] = flag_mask
				end
			end

			col_index += grapheme_width
		end
	end

	private def clear_previous_wide_overlap!(row_data, col_index)
		return unless col_index.positive?

		base = cell_base(col_index)
		return unless row_data[base + CELL_CHARACTER_OFFSET].nil?

		previous_col = col_index - 1
		previous_base = cell_base(previous_col)
		previous_char = row_data[previous_base + CELL_CHARACTER_OFFSET]
		return unless String === previous_char
		return unless Phlex::TUI::TextWidth.grapheme_width(previous_char) == 2

		row_data[previous_base + CELL_CHARACTER_OFFSET] = " "
		row_data[previous_base + CELL_LINE_OFFSET] = nil
		row_data[previous_base + CELL_FLAGS_OFFSET] = 0
		row_data[base + CELL_CHARACTER_OFFSET] = " "
		row_data[base + CELL_FLAGS_OFFSET] = 0
	end

	private def clear_current_wide_tail!(row_data, col_index)
		return if col_index + 1 >= @width

		base = cell_base(col_index)
		current_char = row_data[base + CELL_CHARACTER_OFFSET]
		return unless String === current_char
		return unless Phlex::TUI::TextWidth.grapheme_width(current_char) == 2

		tail_base = cell_base(col_index + 1)
		return unless row_data[tail_base + CELL_CHARACTER_OFFSET].nil?

		row_data[tail_base + CELL_CHARACTER_OFFSET] = " "
		row_data[tail_base + CELL_LINE_OFFSET] = nil
		row_data[tail_base + CELL_FLAGS_OFFSET] = 0
	end

	private def in_bounds?(row, col)
		row >= 0 && row < @height && col >= 0 && col < @width
	end

	private def cell_base(col)
		col * CELL_STRIDE
	end

	private def raw_cell_line(row, col)
		return unless in_bounds?(row, col)

		@cells[row][cell_base(col) + CELL_LINE_OFFSET]
	end

	private def read_cell_slot(row, col, offset)
		return unless in_bounds?(row, col)

		@cells[row][cell_base(col) + offset]
	end

	private def write_cell_slot(row, col, offset, value)
		return unless in_bounds?(row, col)

		@cells[row][cell_base(col) + offset] = value
	end

	private def get_cell_flag(row, col, mask)
		flags = cell_flags(row, col) || 0
		(flags & mask) != 0
	end

	private def set_cell_flag(row, col, mask, value)
		return unless in_bounds?(row, col)

		base = cell_base(col)
		row_data = @cells[row]
		flags = row_data[base + CELL_FLAGS_OFFSET] || 0

		if value
			row_data[base + CELL_FLAGS_OFFSET] = flags | mask
		else
			row_data[base + CELL_FLAGS_OFFSET] = flags & ~mask
		end
	end
end
