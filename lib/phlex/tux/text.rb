# frozen_string_literal: true

class Phlex::Tux::Text < Phlex::TUI
	CURSOR_COLOR = :black
	CURSOR_BG = :white
	CURSOR_TRAILING_GLYPH = "█"

	def initialize(value: nil, multiline: true, focusable: true, on_selection_change: nil, on_focus: nil, on_blur: nil, **attributes)
		@buffer = normalize_utf8(value.to_s)
		@multiline = multiline
		@focusable = focusable
		@on_selection_change = on_selection_change
		@on_focus = on_focus
		@on_blur = on_blur
		@attributes = attributes
		@graphemes = split_graphemes(@buffer)
		@selection_start = 0
		@selection_length = 0
		@scroll_col = 0
		@scroll_row = 0
		@mouse_selecting = false
		@name = :text
		@node = nil
		@layout = []
		@cursor_index = nil
	end

	attr_reader :selection_start
	attr_reader :selection_length

	def configure(cursor_index: nil)
		@cursor_index = cursor_index
		nil
	end

	def value
		@buffer.dup
	end

	def value=(next_value)
		replace(0, @graphemes.length, next_value.to_s)
	end

	def grapheme_count
		@graphemes.length
	end

	def caret_index
		@selection_start + @selection_length
	end

	def selection_empty?
		@selection_length.zero?
	end

	def selection_range
		cursor = caret_index
		start_index = @selection_start
		if cursor < start_index
			[cursor, start_index]
		else
			[start_index, cursor]
		end
	end

	def selected_text
		start_index, end_index = selection_range
		return "" if start_index == end_index

		(@graphemes[start_index...end_index] || []).join
	end

	def set_selection(start:, length:)
		previous_start = @selection_start
		previous_length = @selection_length
		@selection_start = start
		@selection_length = length
		normalize_selection!

		if previous_start != @selection_start || previous_length != @selection_length
			emit_selection_change!
			request_render!
		end

		nil
	end

	def replace(start_cursor, length, text)
		start_index, end_index = normalized_range(start_cursor, length)
		inserted = split_graphemes(normalize_utf8(text.to_s))

		prefix = @graphemes[0...start_index]
		suffix = @graphemes[end_index..] || []
		next_graphemes = prefix + inserted + suffix
		next_buffer = next_graphemes.join

		buffer_changed = next_buffer != @buffer
		@buffer = next_buffer
		@graphemes = next_graphemes

		cursor = start_index + inserted.length
		@selection_start = cursor
		@selection_length = 0
		emit_selection_change!
		request_render! if buffer_changed
		buffer_changed
	end

	def move_left(extend:)
		if !extend && !selection_empty?
			start_index, = selection_range
			return move_to(start_index, extend: false)
		end

		move_to(caret_index - 1, extend:)
	end

	def move_right(extend:)
		if !extend && !selection_empty?
			_, end_index = selection_range
			return move_to(end_index, extend: false)
		end

		move_to(caret_index + 1, extend:)
	end

	def move_to_line_start(extend:)
		line = line_for_index(caret_index)
		move_to(line[:start_index], extend:)
	end

	def move_to_line_end(extend:)
		line = line_for_index(caret_index)
		move_to(line[:end_index], extend:)
	end

	def move_vertical(delta, extend:)
		return false unless @multiline

		current_index = caret_index
		current_line_index = line_index_for(current_index)
		target_line_index = current_line_index + delta
		target_line_index = 0 if target_line_index < 0
		max_line_index = @layout.length - 1
		target_line_index = max_line_index if target_line_index > max_line_index

		current_line = @layout[current_line_index]
		target_line = @layout[target_line_index]
		column = column_for_index(current_line, current_index)
		target_index = index_for_column(target_line, column)
		move_to(target_index, extend:)
	end

	def move_word_left(extend:)
		move_to(word_left_boundary(caret_index), extend:)
	end

	def move_word_right(extend:)
		move_to(word_right_boundary(caret_index), extend:)
	end

	def word_left_boundary(index)
		i = index

		while i > 0 && whitespace_character?(@graphemes[i - 1])
			i -= 1
		end

		return 0 if i <= 0

		if word_character?(@graphemes[i - 1])
			while i > 0 && word_character?(@graphemes[i - 1])
				i -= 1
			end
		else
			while i > 0
				grapheme = @graphemes[i - 1]
				break if whitespace_character?(grapheme)
				break if word_character?(grapheme)
				i -= 1
			end
		end

		i
	end

	def word_right_boundary(index)
		max = @graphemes.length
		i = index

		while i < max && whitespace_character?(@graphemes[i])
			i += 1
		end

		return max if i >= max

		if word_character?(@graphemes[i])
			while i < max && word_character?(@graphemes[i])
				i += 1
			end
		else
			while i < max
				grapheme = @graphemes[i]
				break if whitespace_character?(grapheme)
				break if word_character?(grapheme)
				i += 1
			end
		end

		i
	end

	def logical_line_start_index(index)
		i = index - 1
		while i >= 0
			return i + 1 if @graphemes[i] == "\n"
			i -= 1
		end

		0
	end

	def view_template
		first_frame = @node.nil?
		viewport_width, viewport_height = viewport_size
		normalize_selection!
		rebuild_layout!(viewport_width)
		follow_index = (Integer === @cursor_index) ? @cursor_index : caret_index
		ensure_index_visible!(follow_index, viewport_width, viewport_height)

		box_attributes = {
			width: :grow,
			height: :grow,
			padding: 0,
			focusable: @focusable,
			name: @name,
			on_mouse_down: :handle_mouse_down,
			on_mouse_move: :handle_mouse_move,
			on_mouse_up: :handle_mouse_up,
		}.merge(@attributes)

		if @focusable
			box_attributes[:on_focus] = :handle_focus
			box_attributes[:on_blur] = :handle_blur
		end

		@node = box(**box_attributes) do
			render_visible_lines(viewport_width, viewport_height)
		end

		request_render! if first_frame
	end

	private def normalize_utf8(text)
		value = text.dup
		value = value.force_encoding(Encoding::UTF_8) unless value.encoding == Encoding::UTF_8
		return value if value.valid_encoding?

		value.scrub
	end

	private def split_graphemes(text)
		result = []
		Phlex::TUI::TextWidth.each_grapheme(text) do |grapheme|
			result << grapheme
		end
		result
	end

	private def viewport_size
		node = @node
		return [1, 1] unless node

		width = node.viewport_width
		height = node.viewport_height
		width = 1 unless Integer === width && width > 0
		height = 1 unless Integer === height && height > 0
		[width, height]
	end

	private def normalized_range(start_cursor, length)
		max = @graphemes.length
		left = start_cursor
		right = start_cursor + length
		if right < left
			left, right = right, left
		end

		left = [[left, 0].max, max].min
		right = [[right, 0].max, max].min
		[left, right]
	end

	private def normalize_selection!
		max = @graphemes.length
		start_index = [[@selection_start, 0].max, max].min
		cursor = [[caret_index, 0].max, max].min
		@selection_start = start_index
		@selection_length = cursor - start_index
	end

	private def emit_selection_change!
		@on_selection_change&.call(@selection_start, @selection_length)
		nil
	end

	private def move_to(index, extend:)
		target = [[index, 0].max, @graphemes.length].min
		previous_start = @selection_start
		previous_length = @selection_length

		if extend
			@selection_length = target - @selection_start
		else
			@selection_start = target
			@selection_length = 0
		end

		if previous_start != @selection_start || previous_length != @selection_length
			emit_selection_change!
			request_render!
			return true
		end

		false
	end

	private def rebuild_layout!(wrap_width)
		width = [wrap_width, 1].max
		lines = []
		current_indices = []
		current_start = 0
		current_width = 0
		i = 0
		max = @graphemes.length

		while i < max
			grapheme = @graphemes[i]

			if grapheme == "\n"
				lines << {
					start_index: current_start,
					end_index: i,
					indices: current_indices,
					width: current_width,
				}
				current_indices = []
				current_start = i + 1
				current_width = 0
				i += 1
				next
			end

			grapheme_width = Phlex::TUI::TextWidth.grapheme_width(grapheme)

			if @multiline && !current_indices.empty? && (current_width + grapheme_width) > width
				lines << {
					start_index: current_start,
					end_index: i,
					indices: current_indices,
					width: current_width,
				}
				current_indices = []
				current_start = i
				current_width = 0
				next
			end

			current_indices << i
			current_width += grapheme_width
			i += 1
		end

		lines << {
			start_index: current_start,
			end_index: max,
			indices: current_indices,
			width: current_width,
		}

		@layout = lines
	end

	private def ensure_index_visible!(index, viewport_width, viewport_height)
		line_index = line_index_for(index)
		if line_index < @scroll_row
			@scroll_row = line_index
		elsif line_index >= (@scroll_row + viewport_height)
			@scroll_row = line_index - viewport_height + 1
		end

		@scroll_row = 0 unless @multiline
		max_scroll_row = [@layout.length - viewport_height, 0].max
		@scroll_row = [[@scroll_row, 0].max, max_scroll_row].min

		if @multiline
			@scroll_col = 0
			return
		end

		line = @layout[0]
		cursor_col = column_for_index(line, index)
		if cursor_col < @scroll_col
			@scroll_col = cursor_col
		elsif cursor_col >= (@scroll_col + viewport_width)
			@scroll_col = cursor_col - viewport_width + 1
		end

		max_scroll_col = [line[:width] - viewport_width + 1, 0].max
		@scroll_col = [[@scroll_col, 0].max, max_scroll_col].min
	end

	private def render_visible_lines(viewport_width, viewport_height)
		visible_count = 0
		line_index = @multiline ? @scroll_row : 0
		max_lines = @multiline ? viewport_height : 1

		while visible_count < max_lines
			line = @layout[line_index]
			if line
				render_line(line, viewport_width, line_index)
			else
				paragraph(" ")
			end

			visible_count += 1
			line_index += 1
		end
	end

	private def render_line(line, viewport_width, line_index)
		paragraph(trim_trailing_whitespace: false) do
			line_start_col = @multiline ? 0 : @scroll_col
			line_end_col = line_start_col + viewport_width
			current_col = 0
			sel_start, sel_end = selection_range
			cursor = @cursor_index
			show_cursor = Integer === cursor && selection_empty?
			cursor_rendered = false
			emitted = false

			line[:indices].each do |index|
				grapheme = @graphemes[index]
				width = Phlex::TUI::TextWidth.grapheme_width(grapheme)
				next_col = current_col + width
				selected = index >= sel_start && index < sel_end

				if next_col > line_start_col && current_col < line_end_col
					if show_cursor && !cursor_rendered && cursor == index
						span(grapheme, color: CURSOR_COLOR, bg: CURSOR_BG)
						cursor_rendered = true
						emitted = true
					else
						span(grapheme, inverse: selected)
						emitted = true
					end
				end

				current_col = next_col
			end

			if show_cursor && !cursor_rendered && cursor == line[:end_index] && current_col >= line_start_col && current_col < line_end_col
				span(CURSOR_TRAILING_GLYPH, color: CURSOR_BG)
				cursor_rendered = true
				emitted = true
			end

			if !cursor_rendered && show_cursor && cursor == line[:end_index] && line_index == line_index_for(cursor)
				span(CURSOR_TRAILING_GLYPH, color: CURSOR_BG)
				emitted = true
			end

			unless emitted
				span(" ")
			end
		end
	end

	private def handle_mouse_down(event)
		@node&.focus
		index = index_at_mouse(event)
		return false unless Integer === index

		set_selection(start: index, length: 0)
		@mouse_selecting = true
		event.prevent_default!
		true
	end

	private def handle_focus(event)
		@on_focus&.call(event)
		request_render!
		true
	end

	private def handle_blur(event)
		set_selection(start: caret_index, length: 0)
		@on_blur&.call(event)
		request_render!
		true
	end

	private def handle_mouse_move(event)
		return false unless @mouse_selecting

		index = index_at_mouse(event)
		return false unless Integer === index

		set_selection(start: @selection_start, length: index - @selection_start)
		event.prevent_default!
		true
	end

	private def handle_mouse_up(event)
		return false unless @mouse_selecting

		@mouse_selecting = false
		event.prevent_default!
		true
	end

	private def line_index_for(index)
		i = 0
		while i < @layout.length
			line = @layout[i]
			if index >= line[:start_index] && index <= line[:end_index]
				return i
			end
			i += 1
		end

		[@layout.length - 1, 0].max
	end

	private def line_for_index(index)
		@layout[line_index_for(index)] || @layout[0]
	end

	private def column_for_index(line, index)
		column = 0
		indices = line[:indices]
		i = 0
		while i < indices.length
			grapheme_index = indices[i]
			break if grapheme_index >= index

			column += Phlex::TUI::TextWidth.grapheme_width(@graphemes[grapheme_index])
			i += 1
		end

		column
	end

	private def index_for_column(line, column)
		return line[:start_index] if column <= 0

		current = 0
		indices = line[:indices]
		i = 0
		while i < indices.length
			grapheme_index = indices[i]
			grapheme_width = Phlex::TUI::TextWidth.grapheme_width(@graphemes[grapheme_index])
			next_col = current + grapheme_width
			return grapheme_index if column <= current
			return grapheme_index + 1 if column < next_col

			current = next_col
			i += 1
		end

		line[:end_index]
	end

	private def content_origin
		node = @node
		return nil unless node

		[
			node.row + node.border_top_width + node.padding.top,
			node.col + node.border_left_width + node.padding.left,
		]
	end

	private def index_at_mouse(event)
		origin = content_origin
		return nil unless origin

		origin_row = origin[0]
		origin_col = origin[1]
		local_row = event.row - origin_row
		local_col = event.col - origin_col

		local_row = 0 if local_row < 0
		local_col = 0 if local_col < 0

		if @multiline
			line_index = @scroll_row + local_row
			line_index = @layout.length - 1 if line_index >= @layout.length
			line = @layout[[line_index, 0].max]
			index_for_column(line, local_col)
		else
			line = @layout[0]
			index_for_column(line, @scroll_col + local_col)
		end
	end

	private def word_character?(grapheme)
		/\A[[:alnum:]_]\z/.match?(grapheme)
	end

	private def whitespace_character?(grapheme)
		/\A\s\z/.match?(grapheme)
	end
end
