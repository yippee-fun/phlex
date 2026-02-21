# frozen_string_literal: true

class TUITextTest < Quickdraw::Test
	MouseStubEvent = Struct.new(:row, :col, :default_prevented, keyword_init: true) do
		def prevent_default!
			self.default_prevented = true
		end
	end

	class TextHost < Phlex::TUI
		def initialize(text)
			@text = text
		end

		def view_template
			render(@text)
		end
	end

	private def render_with_app(text, width: 20, height: 1)
		app = Phlex::TUI::App.new
		host = TextHost.new(text)

		2.times do
			app.runtime.begin_frame!
			tree = host.call(Phlex::TUI::Tree.new, context: app)
			Phlex::TUI::Render.new(tree, width:, height:).call
			app.runtime.finalize_frame!
		end

		[app, text]
	end

	test "text selection collapses on blur" do
		app = Phlex::TUI::App.new
		text = Phlex::Tux::Text.new(value: "hello", width: 20, height: 1)
		host = TextHost.new(text)

		app.runtime.begin_frame!
		host.call(Phlex::TUI::Tree.new, context: app)
		app.runtime.finalize_frame!
		app.runtime.focus_next!

		text.set_selection(start: 5, length: -1)
		assert_equal(-1, text.selection_length)

		app.runtime.dispatch(app.runtime.focused_id, Phlex::TUI::BlurEvent.new)

		assert_equal 0, text.selection_length
		assert_equal 4, text.selection_start
	end

	test "ctrl q copies selected text" do
		app = Phlex::TUI::App.new
		text = Phlex::Tux::Text.new(value: "hello", width: 20, height: 1)
		host = TextHost.new(text)

		app.runtime.begin_frame!
		host.call(Phlex::TUI::Tree.new, context: app)
		app.runtime.finalize_frame!
		app.runtime.focus_next!

		text.set_selection(start: 5, length: -1)
		app.__send__(:handle_input, "\u0011")

		assert_equal "o", app.paste_from_clipboard
	end

	test "mouse drag right keeps clicked variable-width glyph included" do
		_text_app, text = render_with_app(Phlex::Tux::Text.new(value: "mm", width: 20, height: 1), width: 20, height: 1)

		down = MouseStubEvent.new(row: 0, col: 1)
		move = MouseStubEvent.new(row: 0, col: 2)

		text.__send__(:handle_mouse_down, down)
		text.__send__(:handle_mouse_move, move)

		assert_equal "m", text.selected_text
	end

	test "mouse drag left keeps clicked variable-width glyph included" do
		_text_app, text = render_with_app(Phlex::Tux::Text.new(value: "mm", width: 20, height: 1), width: 20, height: 1)

		down = MouseStubEvent.new(row: 0, col: 2)
		move = MouseStubEvent.new(row: 0, col: 1)

		text.__send__(:handle_mouse_down, down)
		text.__send__(:handle_mouse_move, move)

		assert_equal "m", text.selected_text
	end

	test "double click selects token under cursor" do
		_text_app, text = render_with_app(Phlex::Tux::Text.new(value: "hello world", width: 20, height: 1), width: 20, height: 1)

		event = MouseStubEvent.new(row: 0, col: 1)
		text.__send__(:handle_mouse_down, event)
		text.__send__(:handle_mouse_up, event)
		text.__send__(:handle_mouse_down, event)

		assert_equal "hello", text.selected_text
	end

	test "double click hold drag extends selection" do
		_text_app, text = render_with_app(Phlex::Tux::Text.new(value: "hello world", width: 20, height: 1), width: 20, height: 1)

		event = MouseStubEvent.new(row: 0, col: 1)
		move = MouseStubEvent.new(row: 0, col: 7)

		text.__send__(:handle_mouse_down, event)
		text.__send__(:handle_mouse_up, event)
		text.__send__(:handle_mouse_down, event)
		text.__send__(:handle_mouse_move, move)

		assert_equal "hello wo", text.selected_text
	end
end
