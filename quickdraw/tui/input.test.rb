# frozen_string_literal: true

class TUIInputTest < Quickdraw::Test
	class InputHost < Phlex::TUI
		def initialize(input)
			@input = input
		end

		def view_template
			render(@input)
		end
	end

	private def focused_input(value: "", multiline: false, **attributes)
		app = Phlex::TUI::App.new
		input = Phlex::Tux::Input.new(value:, multiline:, **attributes)
		host = InputHost.new(input)

		app.runtime.begin_frame!
		host.call(Phlex::TUI::Tree.new, context: app)
		app.runtime.finalize_frame!
		app.runtime.focus_next!

		[app, input]
	end

	private def caret_index(input)
		text = input.instance_variable_get(:@text)
		text.caret_index
	end

	private def selection_start(input)
		text = input.instance_variable_get(:@text)
		text.selection_start
	end

	private def selection_length(input)
		text = input.instance_variable_get(:@text)
		text.selection_length
	end

	test "typing updates input value" do
		app, input = focused_input(width: 20, height: 1)

		app.__send__(:handle_input, "h")
		app.__send__(:handle_input, "i")

		assert_equal "hi", input.value
	end

	test "single line paste replaces newlines with spaces" do
		app, input = focused_input(width: 20, height: 1)

		app.__send__(:handle_input, "\e[200~")
		app.__send__(:handle_input, "a")
		app.__send__(:handle_input, "\n")
		app.__send__(:handle_input, "b")
		app.__send__(:handle_input, "\e[201~")

		assert_equal "a b", input.value
	end

	test "alt left moves by word" do
		app, input = focused_input(value: "hello world", width: 20, height: 1)

		app.__send__(:handle_input, "\e[1;3D")

		assert_equal 6, caret_index(input)
	end

	test "alt left fallback sequence moves by word" do
		app, input = focused_input(value: "hello world", width: 20, height: 1)

		app.__send__(:handle_input, "\eb")

		assert_equal 6, caret_index(input)
	end

	test "alt left double-escape sequence moves by word" do
		app, input = focused_input(value: "hello world", width: 20, height: 1)

		app.__send__(:handle_input, "\e\e[D")

		assert_equal 6, caret_index(input)
	end

	test "shift left extends selection" do
		app, input = focused_input(value: "hello", width: 20, height: 1)

		app.__send__(:handle_input, "\e[1;2D")

		assert_equal 5, selection_start(input)
		assert_equal(-1, selection_length(input))
	end

	test "cmd left moves to line start" do
		app, input = focused_input(value: "hello", width: 20, height: 1)

		app.__send__(:handle_input, "\e[1;9D")
		app.__send__(:handle_input, "X")

		assert_equal "Xhello", input.value
	end

	test "ctrl v pastes from app clipboard" do
		app, input = focused_input(width: 20, height: 1)
		app.copy_to_clipboard("paste")

		app.__send__(:handle_input, "\u0016")

		assert_equal "paste", input.value
	end

	test "alt backspace deletes previous word" do
		app, input = focused_input(value: "hello world", width: 20, height: 1)

		app.__send__(:handle_input, "\e\177")

		assert_equal "hello ", input.value
	end

	test "cmd backspace deletes to line start" do
		app, input = focused_input(value: "hello world", width: 20, height: 1)

		app.__send__(:handle_input, "\u0015")

		assert_equal "", input.value
	end

	test "placeholder remains visible while focused when empty" do
		app = Phlex::TUI::App.new
		input = Phlex::Tux::Input.new(placeholder: "Type here", width: 20, height: 1)
		host = InputHost.new(input)

		app.runtime.begin_frame!
		tree = host.call(Phlex::TUI::Tree.new, context: app)
		app.runtime.finalize_frame!
		app.runtime.focus_next!

		renderer = Phlex::TUI::Render.new(tree, width: 20, height: 1)
		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal true, output.include?("Type here")
	end

	test "binary utf-8 input inserts smart apostrophe" do
		app, input = focused_input(width: 20, height: 1)

		app.__send__(:handle_input, "’".dup.force_encoding(Encoding::ASCII_8BIT))

		assert_equal "’", input.value
	end

	test "readonly input ignores text mutations" do
		app, input = focused_input(value: "hello", readonly: true, width: 20, height: 1)

		app.__send__(:handle_input, "x")
		app.__send__(:handle_input, "\177")

		assert_equal "hello", input.value
	end

	test "selection collapses on blur" do
		app, input = focused_input(value: "hello", width: 20, height: 1)

		app.__send__(:handle_input, "\e[1;2D")
		assert_equal(-1, selection_length(input))

		input.__send__(:handle_blur, Phlex::TUI::BlurEvent.new)

		assert_equal 0, selection_length(input)
		assert_equal 4, selection_start(input)
	end

	test "ctrl g copies current selection" do
		app, input = focused_input(value: "hello", width: 20, height: 1)

		app.__send__(:handle_input, "\e[1;2D")
		app.__send__(:handle_input, "\u0007")

		assert_equal "o", app.paste_from_clipboard
		assert_equal "hello", input.value
	end
end
