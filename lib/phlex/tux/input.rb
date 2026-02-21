# frozen_string_literal: true

class Phlex::Tux::Input < Phlex::TUI
	CURSOR_COLOR = :black
	CURSOR_BG = :white
	CURSOR_TRAILING_GLYPH = "█"

	def initialize(value: nil, placeholder: nil, multiline: false, readonly: false, on_change: nil, on_focus: nil, on_blur: nil, **attributes)
		@placeholder = placeholder
		@multiline = multiline
		@readonly = readonly
		@on_change = on_change
		@on_focus = on_focus
		@on_blur = on_blur
		@attributes = attributes
		@name = :input
		@text = Phlex::Tux::Text.new(value:, multiline:, focusable: false)
		@text.set_selection(start: @text.grapheme_count, length: 0)
	end

	def value
		@text.value
	end

	def value=(next_value)
		@text.value = next_value.to_s
		@on_change&.call(@text.value)
	end

	def readonly?
		@readonly
	end

	def view_template
		@node = box(
			focusable: true,
			name: @name,
			on_key_down: :handle_key_down,
			on_text_input: :handle_text_input,
			on_focus: :handle_focus,
			on_blur: :handle_blur,
			on_mouse_down: :handle_mouse_down,
			**@attributes
		) do
			render_content
		end
	end

	private def render_content
		if @text.value.empty? && @placeholder
			render_placeholder
		else
			cursor = focused?(@name) ? @text.caret_index : nil
			@text.configure(cursor_index: cursor)
			render(@text)
		end
	end

	private def render_placeholder
		if focused?(@name) && @text.selection_empty? && @text.caret_index.zero?
			placeholder_graphemes = split_graphemes(@placeholder)
			paragraph(trim_trailing_whitespace: false) do
				first = placeholder_graphemes[0]
				if first
					span(first, color: CURSOR_COLOR, bg: CURSOR_BG)
					rest = placeholder_graphemes[1..]
					span(rest.join, color: :bright_black) if rest && !rest.empty?
				else
					span(CURSOR_TRAILING_GLYPH, color: CURSOR_COLOR, bg: CURSOR_BG)
				end
			end
		else
			paragraph(@placeholder, color: :bright_black)
		end
	end

	private def handle_mouse_down(event)
		@node&.focus
		if @text.value.empty?
			@text.set_selection(start: 0, length: 0)
			request_render!
		end
		event.prevent_default!
		true
	end

	private def handle_text_input(event)
		if @readonly
			event.prevent_default!
			return
		end

		text = normalize_input_text(event.text)
		return if text.empty?

		insert_text(text)
		event.prevent_default!
	end

	private def handle_key_down(event)
		key = event.key
		handled = case key
		in :left
			@text.move_left(extend: false)
		in :shift_left
			@text.move_left(extend: true)
		in :right
			@text.move_right(extend: false)
		in :shift_right
			@text.move_right(extend: true)
		in :up
			@text.move_vertical(-1, extend: false)
		in :shift_up
			@text.move_vertical(-1, extend: true)
		in :down
			@text.move_vertical(1, extend: false)
		in :shift_down
			@text.move_vertical(1, extend: true)
		in :home | :cmd_left
			@text.move_to_line_start(extend: false)
		in :shift_cmd_left
			@text.move_to_line_start(extend: true)
		in :end | :cmd_right
			@text.move_to_line_end(extend: false)
		in :shift_cmd_right
			@text.move_to_line_end(extend: true)
		in :alt_left
			@text.move_word_left(extend: false)
		in :shift_alt_left
			@text.move_word_left(extend: true)
		in :alt_right
			@text.move_word_right(extend: false)
		in :shift_alt_right
			@text.move_word_right(extend: true)
		in :backspace
			@readonly ? false : backspace
		in :alt_backspace
			@readonly ? false : delete_word_left
		in :cmd_backspace
			@readonly ? false : delete_to_line_start
		in :delete
			@readonly ? false : delete_forward
		in :enter
			@readonly ? false : handle_enter
		in :ctrl_q
			copy_selection
		in :ctrl_g
			copy_selection
		in :alt_c
			copy_selection
		in :ctrl_x
			@readonly ? false : cut_selection
		in :ctrl_v
			@readonly ? false : paste_from_clipboard
		else
			false
		end

		event.prevent_default! if handled
	end

	private def replace_selection(text)
		start_index, end_index = @text.selection_range
		changed = @text.replace(start_index, end_index - start_index, text)
		if changed
			@on_change&.call(@text.value)
			request_render!
		end
		changed
	end

	private def insert_text(text)
		replace_selection(text)
	end

	private def backspace
		if @text.selection_empty?
			cursor = @text.caret_index
			return false if cursor <= 0

			changed = @text.replace(cursor - 1, 1, "")
			if changed
				@on_change&.call(@text.value)
				request_render!
			end

			changed
		else
			replace_selection("")
		end
	end

	private def delete_forward
		if @text.selection_empty?
			cursor = @text.caret_index
			return false if cursor >= @text.grapheme_count

			changed = @text.replace(cursor, 1, "")
			if changed
				@on_change&.call(@text.value)
				request_render!
			end

			changed
		else
			replace_selection("")
		end
	end

	private def delete_word_left
		if !@text.selection_empty?
			return replace_selection("")
		end

		cursor = @text.caret_index
		return false if cursor <= 0

		start_index = @text.word_left_boundary(cursor)
		changed = @text.replace(start_index, cursor - start_index, "")
		if changed
			@on_change&.call(@text.value)
			request_render!
		end
		changed
	end

	private def delete_to_line_start
		if !@text.selection_empty?
			return replace_selection("")
		end

		cursor = @text.caret_index
		return false if cursor <= 0

		line_start = @text.logical_line_start_index(cursor)
		return false if line_start == cursor

		changed = @text.replace(line_start, cursor - line_start, "")
		if changed
			@on_change&.call(@text.value)
			request_render!
		end
		changed
	end

	private def handle_enter
		return false unless @multiline

		insert_text("\n")
	end

	private def copy_selection
		text = @text.selected_text
		return false if text.empty?

		app&.copy_to_clipboard(text)
		true
	end

	private def cut_selection
		return false unless copy_selection

		replace_selection("")
	end

	private def paste_from_clipboard
		text = app&.paste_from_clipboard
		return false if text.nil? || text.empty?

		insert_text(normalize_input_text(text))
	end

	private def normalize_input_text(text)
		normalized = text.dup
		normalized = normalized.force_encoding(Encoding::UTF_8) unless normalized.encoding == Encoding::UTF_8
		normalized = normalized.scrub unless normalized.valid_encoding?
		normalized = normalized.gsub("\r\n", "\n").tr("\r", "\n")
		if @multiline
			normalized
		else
			normalized.tr("\n", " ")
		end
	end

	private def split_graphemes(text)
		result = []
		Phlex::TUI::TextWidth.each_grapheme(text) do |grapheme|
			result << grapheme
		end
		result
	end

	private def handle_focus(event)
		@on_focus&.call(event)
		request_render!
		true
	end

	private def handle_blur(event)
		@text.set_selection(start: @text.caret_index, length: 0)
		@on_blur&.call(event)
		request_render!
		true
	end
end
