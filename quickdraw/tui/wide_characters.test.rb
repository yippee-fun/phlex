# frozen_string_literal: true

class TUIWideCharactersTest < Quickdraw::Test
	class WideParagraphExample < Phlex::TUI
		def view_template
			box(width: 2, height: 1) do
				paragraph("😀a")
			end
		end
	end

	test "paint_text writes continuation cell as nil for wide graphemes" do
		canvas = Phlex::TUI::Canvas.new(width: 4, height: 1)
		canvas.paint_text(row: 0, col: 0, text: "😀A")

		assert_equal "😀", canvas.cell_character(0, 0)
		assert_equal nil, canvas.cell_character(0, 1)
		assert_equal "A", canvas.cell_character(0, 2)
		assert_equal "😀A ", canvas.styled_lines.first.gsub(/\e\[[\d;]*m/, "")
	end

	test "overwriting a continuation cell clears the previous wide glyph" do
		canvas = Phlex::TUI::Canvas.new(width: 3, height: 1)
		canvas.paint_text(row: 0, col: 0, text: "😀")
		canvas.paint_text(row: 0, col: 1, text: "B")

		assert_equal " ", canvas.cell_character(0, 0)
		assert_equal "B", canvas.cell_character(0, 1)
		assert_equal " B ", canvas.styled_lines.first.gsub(/\e\[[\d;]*m/, "")
	end

	test "paragraph clipping uses display width for emoji" do
		renderer = Phlex::TUI::Render.new(WideParagraphExample.new.call, width: 2, height: 1)
		renderer.call

		assert_equal "😀", renderer.canvas.cell_character(0, 0)
		assert_equal nil, renderer.canvas.cell_character(0, 1)
	end
end
