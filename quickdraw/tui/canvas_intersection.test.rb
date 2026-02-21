# frozen_string_literal: true

class TUICanvasIntersectionTest < Quickdraw::Test
	test "crossing border lines merge into a single intersection glyph" do
		canvas = render_cross(horizontal: :thin, vertical: :thin)

		assert_equal canvas.to_s, <<~CANVAS.chomp
     │  
     │  
   ──┼──
     │  
     │  
				CANVAS
	end

	test "mixed thin horizontal and thick vertical lines use the heavy vertical cross glyph" do
		canvas = render_cross(horizontal: :thin, vertical: :thick)

		assert_equal canvas.to_s, <<~CANVAS.chomp
     ┃  
     ┃  
   ──╂──
     ┃  
     ┃  
				CANVAS
	end

	test "mixed thick horizontal and thin vertical lines use the heavy horizontal cross glyph" do
		canvas = render_cross(horizontal: :thick, vertical: :thin)

		assert_equal canvas.to_s, <<~CANVAS.chomp
     │  
     │  
   ━━┿━━
     │  
     │  
				CANVAS
	end

	test "mixed double horizontal and thin vertical lines preserve double-line horizontals" do
		canvas = render_cross(horizontal: :double, vertical: :thin)

		assert_equal canvas.to_s, <<~CANVAS.chomp
     │  
     │  
   ══╪══
     │  
     │  
				CANVAS
	end

	test "intersection rendering is stable regardless of draw order" do
		horizontal_first = render_cross(horizontal: :thin, vertical: :thick, order: :horizontal_first)
		vertical_first = render_cross(horizontal: :thin, vertical: :thick, order: :vertical_first)

		assert_equal horizontal_first.to_s, vertical_first.to_s
	end

	test "clipped drawing still updates neighboring line cells when they already exist" do
		canvas = Phlex::TUI::Canvas.new(width: 5, height: 5)
		canvas.draw_vertical_line(0, 2, height: 5, style: :thin)

		canvas.with_clip(row: 2, col: 0, width: 2, height: 1) do
			canvas.draw_horizontal_line(2, 0, width: 5, style: :thin)
		end

		assert_equal canvas.to_s, <<~CANVAS.chomp
     │  
     │  
   ──┼  
     │  
     │  
				CANVAS
	end

	test "painting a line cell outside the canvas is a no-op" do
		canvas = Phlex::TUI::Canvas.new(width: 2, height: 2)
		canvas.paint_line_cell(-1, 0, [0, 1, 0, 1])
		canvas.paint_line_cell(0, -1, [1, 0, 1, 0])
		canvas.paint_line_cell(2, 1, [0, 1, 0, 1])
		canvas.paint_line_cell(1, 2, [1, 0, 1, 0])

		assert_equal canvas.to_s, "  \n  "
	end

	test "line drawing over text does not inherit overwritten text color" do
		canvas = Phlex::TUI::Canvas.new(width: 1, height: 1)
		canvas.paint_text(row: 0, col: 0, text: "A", color: :red)
		canvas.paint_line_cell(0, 0, [0, 1, 0, 1])

		assert_equal canvas.cell_character(0, 0), "─"
		assert_equal canvas.cell_color(0, 0), nil
	end

	test "rounded corners normalize to straight intersections when merged" do
		canvas = Phlex::TUI::Canvas.new(width: 5, height: 5)
		canvas.paint_top_left_corner(2, 2, 4)
		canvas.draw_horizontal_line(2, 1, width: 4, style: :thin)

		assert_equal canvas.lines[2], " ─┬──"
	end

	private def render_cross(horizontal:, vertical:, order: :horizontal_first)
		canvas = Phlex::TUI::Canvas.new(width: 5, height: 5)

		if order == :vertical_first
			canvas.draw_vertical_line(0, 2, height: 5, style: vertical)
			canvas.draw_horizontal_line(2, 0, width: 5, style: horizontal)
		else
			canvas.draw_horizontal_line(2, 0, width: 5, style: horizontal)
			canvas.draw_vertical_line(0, 2, height: 5, style: vertical)
		end

		canvas
	end
end
