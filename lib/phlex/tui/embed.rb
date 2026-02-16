# frozen_string_literal: true

class Phlex::TUI::Embed < Phlex::TUI::Node
	CSI_PATTERN = /\e\[([0-9;?]*)([@-~])/

	def initialize(
		width: :fit,
		height: :fit,
		min_width: nil,
		min_height: nil,
		max_width: nil,
		max_height: nil,
		parent: nil,
		&block
	)
		raise ArgumentError, "embed requires a block" unless block

		@parent = parent
		@block = block
		@block_ignores_height = block_ignores_height?(block)
		@cached_renderer_id = nil
		@cached_content = {}
		@requested_width = normalize_requested_dimension(width, :width)
		@requested_height = normalize_requested_dimension(height, :height)

		initial_width = (Integer === @requested_width) ? @requested_width : (min_width || 0)
		initial_height = (Integer === @requested_height) ? @requested_height : (min_height || 0)

		initialize_geometry(
			width: initial_width,
			height: initial_height,
			min_width: min_width || ((Integer === @requested_width) ? @requested_width : 0),
			min_height: min_height || ((Integer === @requested_height) ? @requested_height : 0),
			max_width: max_width || ((Integer === @requested_width) ? @requested_width : Float::INFINITY),
			max_height: max_height || ((Integer === @requested_height) ? @requested_height : Float::INFINITY),
		)
	end

	attr_reader :requested_width
	attr_reader :requested_height

	def fit_width(renderer)
		return unless requested_width == :fit

		height_hint = (Integer === requested_height) ? clamp(requested_height, min_height, max_height) : nil

		natural_width, = measured_size(renderer:, width: nil, height: height_hint)
		self.width = clamp(natural_width, min_width, max_width)
	end

	def fit_height(renderer)
		return unless requested_height == :fit

		width_hint = if Integer === requested_width
			clamp(requested_width, min_width, max_width)
		elsif Integer === width
			width
		end

		_, natural_height, measured_text = measured_size(renderer:, width: width_hint, height: nil)
		final_height = clamp(natural_height, min_height, max_height)
		self.height = final_height

		if Integer === width_hint
			alias_cached_content(renderer:, source_width: width_hint, source_height: nil, target_width: width_hint, target_height: final_height, text: measured_text)
		end
	end

	def draw(renderer)
		render_width = [width, 0].max
		render_height = [height, 0].max
		return if render_width.zero? || render_height.zero?

		text = render_content(renderer:, width: render_width, height: render_height)
		rows = parse_styled_rows(text, renderer)
		draw_rows(renderer, normalize_rows(rows, render_width, render_height))
	end

	private def draw_rows(renderer, rows)
		rows.each_with_index do |cells, row_offset|
			next if cells.empty?

			cursor = 0
			while cursor < cells.length
				style = cells[cursor][:style]
				run_start = cursor
				cursor += 1

				while cursor < cells.length && cells[cursor][:style] == style
					cursor += 1
				end

				text = cells[run_start...cursor].map { |cell| cell[:character] }.join
				paint_run(renderer, row_offset, run_start, text, style)
			end
		end
	end

	private def paint_run(renderer, row_offset, col_offset, text, style)
		renderer.canvas.paint_text(
			row: row + row_offset,
			col: col + col_offset,
			text:,
			color: style[:color],
			bg: style[:bg],
			bold: style[:bold],
			italic: style[:italic],
			underline: style[:underline],
			blink: style[:blink],
			inverse: style[:inverse],
			strikethrough: style[:strikethrough],
		)
	end

	private def normalize_rows(rows, width, height)
		result = Array.new(height) { empty_row(width) }

		row_limit = [rows.length, height].min
		row_index = 0
		while row_index < row_limit
			source = rows[row_index]
			col_limit = [source.length, width].min

			col_index = 0
			while col_index < col_limit
				result[row_index][col_index] = source[col_index]
				col_index += 1
			end

			row_index += 1
		end

		result
	end

	private def empty_row(width)
		Array.new(width) do
			{
				character: " ",
				style: default_style,
			}
		end
	end

	private def measured_size(renderer:, width:, height:)
		text = render_content(renderer:, width:, height:)
		visible_lines = parse_visible_lines(text)
		natural_width = visible_lines.map(&:length).max || 0
		natural_height = visible_lines.length

		[natural_width, natural_height, text]
	end

	private def alias_cached_content(renderer:, source_width:, source_height:, target_width:, target_height:, text:)
		cache = cache_for_renderer(renderer)
		cache[[source_width, source_height]] = text
		cache[[target_width, target_height]] ||= text
	end

	private def parse_visible_lines(text)
		return [] if text.empty?

		lines = [[]]
		each_token(text) do |token|
			case token[:type]
			in :character
				lines.last << token[:value]
			in :newline
				lines << []
			else
				next
			end
		end

		lines.map(&:join)
	end

	private def parse_styled_rows(text, renderer)
		return [] if text.empty?

		base_style = style_from_parent(renderer)
		current_style = base_style.dup
		rows = [[]]

		each_token(text) do |token|
			case token[:type]
			in :character
				rows.last << {
					character: token[:value],
					style: current_style.dup,
				}
			in :newline
				rows << []
			in :sgr
				apply_sgr!(current_style, base_style, token[:params], renderer)
			end
		end

		rows
	end

	private def each_token(text)
		index = 0
		while index < text.length
			if (match = CSI_PATTERN.match(text, index)) && match.begin(0) == index
				params = match[1]
				final = match[2]
				yield({ type: :sgr, params: }) if final == "m"
				index = match.end(0)
				next
			end

			character = text[index]
			if character == "\e"
				index += 1
				next
			end

			yield((character == "\n") ? { type: :newline } : { type: :character, value: character })
			index += 1
		end
	end

	private def style_from_parent(renderer)
		{
			bold: parent&.bold,
			italic: parent&.italic,
			underline: parent&.underline,
			blink: parent&.blink,
			inverse: parent&.inverse,
			strikethrough: parent&.strikethrough,
			color: resolve_parent_color(renderer, parent&.color),
			bg: resolve_parent_color(renderer, parent&.bg),
		}
	end

	private def resolve_parent_color(renderer, color)
		return nil if color.nil?

		renderer.canvas.resolve_rgb(color)
	end

	private def apply_sgr!(style, base_style, params, renderer)
		codes = if params.nil? || params.empty?
			[0]
		else
			params.split(";").map { |value| value.empty? ? 0 : value.to_i }
		end

		index = 0
		while index < codes.length
			code = codes[index]

			case code
			when 0
				style.replace(base_style)
			when 1
				style[:bold] = true
			when 3
				style[:italic] = true
			when 4
				style[:underline] = true
			when 5
				style[:blink] = true
			when 7
				style[:inverse] = true
			when 9
				style[:strikethrough] = true
			when 22
				style[:bold] = false
			when 23
				style[:italic] = false
			when 24
				style[:underline] = false
			when 25
				style[:blink] = false
			when 27
				style[:inverse] = false
			when 29
				style[:strikethrough] = false
			when 39
				style[:color] = base_style[:color]
			when 49
				style[:bg] = base_style[:bg]
			when 30..37
				style[:color] = renderer.canvas.terminal_color(ansi_color_symbol(code))
			when 40..47
				style[:bg] = renderer.canvas.terminal_color(ansi_bg_color_symbol(code))
			when 90..97
				style[:color] = renderer.canvas.terminal_color(ansi_bright_color_symbol(code))
			when 100..107
				style[:bg] = renderer.canvas.terminal_color(ansi_bright_bg_color_symbol(code))
			when 38
				index = apply_extended_color!(style, :color, codes, index, renderer)
			when 48
				index = apply_extended_color!(style, :bg, codes, index, renderer)
			end

			index += 1
		end
	end

	private def apply_extended_color!(style, key, codes, index, renderer)
		mode = codes[index + 1]
		return index if mode.nil?

		case mode
		when 5
			palette_index = codes[index + 2]
			return index if palette_index.nil?

			style[key] = renderer.canvas.ansi256_to_rgb(palette_index)
			index + 2
		when 2
			r = codes[index + 2]
			g = codes[index + 3]
			b = codes[index + 4]
			return index if r.nil? || g.nil? || b.nil?

			style[key] = [r, g, b]
			index + 4
		else
			index
		end
	end

	private def ansi_color_symbol(code)
		[
			:black,
			:red,
			:green,
			:yellow,
			:blue,
			:magenta,
			:cyan,
			:white,
		][code - 30]
	end

	private def ansi_bg_color_symbol(code)
		[
			:black,
			:red,
			:green,
			:yellow,
			:blue,
			:magenta,
			:cyan,
			:white,
		][code - 40]
	end

	private def ansi_bright_color_symbol(code)
		[
			:bright_black,
			:bright_red,
			:bright_green,
			:bright_yellow,
			:bright_blue,
			:bright_magenta,
			:bright_cyan,
			:bright_white,
		][code - 90]
	end

	private def ansi_bright_bg_color_symbol(code)
		[
			:bright_black,
			:bright_red,
			:bright_green,
			:bright_yellow,
			:bright_blue,
			:bright_magenta,
			:bright_cyan,
			:bright_white,
		][code - 100]
	end

	private def render_content(renderer:, width:, height:)
		cache = cache_for_renderer(renderer)
		key = [width, height]
		return cache[key] if cache.key?(key)

		if @block_ignores_height && !height.nil?
			unbounded_key = [width, nil]
			if cache.key?(unbounded_key)
				cache[key] = cache[unbounded_key]
				return cache[key]
			end
		end

		cache[key] = @block.call(width, height).to_s
	end

	private def block_ignores_height?(block)
		parameters = block.parameters
		has_rest = parameters.any? { |type, _| type == :rest }
		return false if has_rest

		positional_count = parameters.count { |type, _| type == :req || type == :opt }
		positional_count <= 1
	end

	private def cache_for_renderer(renderer)
		renderer_id = renderer.object_id
		if @cached_renderer_id != renderer_id
			@cached_renderer_id = renderer_id
			@cached_content = {}
		end

		@cached_content
	end

	private def default_style
		{
			bold: nil,
			italic: nil,
			underline: nil,
			blink: nil,
			inverse: nil,
			strikethrough: nil,
			color: nil,
			bg: nil,
		}
	end

	private def normalize_requested_dimension(value, name)
		return value if Integer === value && value >= 0
		return value if value == :fit || value == :grow

		raise ArgumentError, "#{name} must be an Integer >= 0, :fit, or :grow"
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end

	private

	attr_reader :parent
end
