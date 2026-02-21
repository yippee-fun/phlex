# frozen_string_literal: true

class TUIBlockTextTest < Quickdraw::Test
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
end
