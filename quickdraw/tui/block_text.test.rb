# frozen_string_literal: true

class TUIBlockTextTest < Quickdraw::Test
		MouseStubEvent = Struct.new(:row, :col, :default_prevented, keyword_init: true) do
				def prevent_default!
						self.default_prevented = true
				end
		end

		TEST_FONT = Phlex::TUI::CompiledFont.new({
				"A" => [
						"▄",
						"█",
				],
				'"' => [
						"▀",
						"▀",
				],
				"B" => [
						"▀",
						"█",
				],
				"U" => [
						"▀",
						"▀",
				],
				"L" => [
						"▄",
						"▄",
				],
				" " => [
						" ",
						" ",
				],
				"?" => [
						"█",
						"█",
				],
		}).freeze

		VARIABLE_WIDTH_FONT = Phlex::TUI::CompiledFont.new({
				"i" => [
						"█",
						"█",
				],
				"m" => [
						"██",
						"██",
				],
				" " => [
						" ",
						" ",
				],
				"?" => [
						"█",
						"█",
				],
		}).freeze

		private def plain_output(component)
				renderer = Phlex::TUI::Render.new(component.call, width: :fit, height: :fit)
				renderer.call.gsub(/\e\[[\d;]*m/, "")
		end

		private def render_with_app(component)
				app = Phlex::TUI::App.new
				tree = component.call(Phlex::TUI::Tree.new, context: app)
				renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)
				renderer.call
				[app, component]
		end

		test "unknown characters fall back to question mark glyph" do
				component = Phlex::Tux::BlockText.new(text: "Z", font: TEST_FONT)

				assert_equal "█\n█", plain_output(component)
		end

		test "word wrapping wraps to the next large-text line" do
				component = Phlex::Tux::BlockText.new(text: "A B", font: TEST_FONT, width: 1, text_wrap: :word)

				assert_equal "▄\n█\n▀\n█", plain_output(component)
		end

		test "pretty wrap balances ragged short last line" do
				component = Phlex::Tux::BlockText.new(text: "A A A A", font: TEST_FONT, width: 5, text_wrap: :pretty)

				assert_equal "▄ ▄\n█ █\n▄ ▄\n█ █", plain_output(component).lines.map(&:rstrip).join("\n")
		end

		test "negative letter spacing overlaps using bit masking" do
				component = Phlex::Tux::BlockText.new(text: "UL", font: TEST_FONT, letter_spacing: -1, text_wrap: :none)

				assert_equal "█\n█", plain_output(component)
		end

		test "line_height below 1 overlaps rows using bit masking" do
				component = Phlex::Tux::BlockText.new(text: "U\nL", font: TEST_FONT, line_height: 0, text_wrap: :none)

				assert_equal "█\n█", plain_output(component)
		end

		test "line_height above 1 inserts proportional gap" do
				component = Phlex::Tux::BlockText.new(text: "U\nL", font: TEST_FONT, line_height: 2, text_wrap: :none)

				assert_equal "▀\n▀\n\n\n▄\n▄", plain_output(component).lines.map(&:rstrip).join("\n")
		end

		test "text_align right aligns each wrapped line independently" do
				component = Phlex::Tux::BlockText.new(text: "A B A", font: TEST_FONT, width: 3, text_align: :right, text_wrap: :word)

				assert_equal "▄ ▀\n█ █\n  ▄\n  █", plain_output(component)
		end

		test "glyph_offset_y shifts glyph rows downward" do
				component = Phlex::Tux::BlockText.new(text: "A", font: TEST_FONT, glyph_offset_y: 1, text_wrap: :none)

				assert_equal " \n▄\n█", plain_output(component)
		end

		test "hanging punctuation pads left and right by one cell" do
				component = Phlex::Tux::BlockText.new(text: "A", font: TEST_FONT, hanging_punctuation: true, text_wrap: :none)

				assert_equal " ▄ \n █ ", plain_output(component)
		end

		test "hanging punctuation reduces wrap content width" do
				component = Phlex::Tux::BlockText.new(text: "A B", font: TEST_FONT, width: 3, hanging_punctuation: true, text_wrap: :word)

				assert_equal " ▄ \n █ \n ▀ \n █ ", plain_output(component)
		end

		test "hanging punctuation moves quote into the side gutter" do
				component = Phlex::Tux::BlockText.new(text: '"A"', font: TEST_FONT, width: 5, text_align: :center, hanging_punctuation: true, text_wrap: :none)

				assert_equal "▀ ▄▀\n▀ █▀", plain_output(component).lines.map(&:rstrip).join("\n")
		end

		test "variable width glyphs wrap by measured glyph width" do
				component = Phlex::Tux::BlockText.new(text: "m i", font: VARIABLE_WIDTH_FONT, width: 3, text_wrap: :word)

				assert_equal "██\n██\n█\n█", plain_output(component).lines.map(&:rstrip).join("\n")
		end

		test "mouse drag updates selection range" do
				component = Phlex::Tux::BlockText.new(text: "AB", font: TEST_FONT, text_wrap: :none)
				render_with_app(component)

				down = MouseStubEvent.new(row: 0, col: 0)
				move = MouseStubEvent.new(row: 0, col: 1)
				up = MouseStubEvent.new(row: 0, col: 1)

				component.__send__(:handle_mouse_down, down)
				component.__send__(:handle_mouse_move, move)
				component.__send__(:handle_mouse_up, up)

				assert_equal true, down.default_prevented
				assert_equal true, move.default_prevented
				assert_equal true, up.default_prevented
				assert_equal "A", component.selected_text
		end

		test "mouse drag right keeps clicked variable-width glyph included" do
				component = Phlex::Tux::BlockText.new(text: "mm", font: VARIABLE_WIDTH_FONT, text_wrap: :none)
				render_with_app(component)

				down = MouseStubEvent.new(row: 0, col: 1)
				move = MouseStubEvent.new(row: 0, col: 2)

				component.__send__(:handle_mouse_down, down)
				component.__send__(:handle_mouse_move, move)

				assert_equal "m", component.selected_text
		end

		test "mouse drag left keeps clicked variable-width glyph included" do
				component = Phlex::Tux::BlockText.new(text: "mm", font: VARIABLE_WIDTH_FONT, text_wrap: :none)
				render_with_app(component)

				down = MouseStubEvent.new(row: 0, col: 2)
				move = MouseStubEvent.new(row: 0, col: 1)

				component.__send__(:handle_mouse_down, down)
				component.__send__(:handle_mouse_move, move)

				assert_equal "mm", component.selected_text
		end

		test "double click selects the token under cursor" do
				component = Phlex::Tux::BlockText.new(text: "A B", font: TEST_FONT, text_wrap: :none)
				render_with_app(component)

				event = MouseStubEvent.new(row: 0, col: 0)
				component.__send__(:handle_mouse_down, event)
				component.__send__(:handle_mouse_up, event)
				component.__send__(:handle_mouse_down, event)

				assert_equal "A", component.selected_text
		end

		test "double click hold drag extends selection" do
				component = Phlex::Tux::BlockText.new(text: "A B A", font: TEST_FONT, text_wrap: :none)
				render_with_app(component)

				event = MouseStubEvent.new(row: 0, col: 0)
				move = MouseStubEvent.new(row: 0, col: 3)

				component.__send__(:handle_mouse_down, event)
				component.__send__(:handle_mouse_up, event)
				component.__send__(:handle_mouse_down, event)
				component.__send__(:handle_mouse_move, move)

				assert_equal "A B ", component.selected_text
		end

		test "ctrl q copies selected text" do
				app, component = render_with_app(Phlex::Tux::BlockText.new(text: "AB", font: TEST_FONT, text_wrap: :none))
				component.set_selection(start: 0, length: 1)

				event = Phlex::TUI::KeyDownEvent.new(key: :ctrl_q, raw: "\u0011")
				component.__send__(:handle_key_down, event)

				assert_equal "A", app.paste_from_clipboard
				assert_equal true, event.default_prevented?
		end

		test "selection overlay keeps wrapped line glyph positions stable" do
				text = "A B A B A"
				component = Phlex::Tux::BlockText.new(text:, font: TEST_FONT, width: 3, text_wrap: :word)
				unselected = plain_output(component)

				component.set_selection(start: 0, length: text.length)
				selected = plain_output(component)

				assert_equal unselected, selected
		end

		test "selection overlay drag across line-height gap keeps nearest line" do
				component = Phlex::Tux::BlockText.new(text: "A\nB\nA", font: TEST_FONT, line_height: 2, text_wrap: :none)
				render_with_app(component)

				down = MouseStubEvent.new(row: 4, col: 0)
				move = MouseStubEvent.new(row: 6, col: 0)

				component.__send__(:handle_mouse_down, down)
				component.__send__(:handle_mouse_move, move)

				assert_equal "", component.selected_text
		end

		test "selection overlay does not freeze when clipped by height" do
				component = Phlex::Tux::BlockText.new(text: "A\nB\nA\nB", font: TEST_FONT, height: 4)
				component.set_selection(start: 0, length: 10)

				output = plain_output(component)
				assert_equal "▄\n█\n▀\n█", output
		end
end
