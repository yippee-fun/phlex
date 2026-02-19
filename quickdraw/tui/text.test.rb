# frozen_string_literal: true

class TUITextTest < Quickdraw::Test
	class TextHost < Phlex::TUI
		def initialize(text)
			@text = text
		end

		def view_template
			render(@text)
		end
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
end
