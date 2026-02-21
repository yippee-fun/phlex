# frozen_string_literal: true

class TUIColorAttributesTest < Quickdraw::Test
	class InlineColorExample < Phlex::TUI
		def view_template
			paragraph("A", color: :red, bg: :blue)
		end
	end

	class InheritedColorExample < Phlex::TUI
		def view_template
			box(color: :yellow) do
				paragraph do
					span("A")
					span("B", color: :cyan)
				end
			end
		end
	end

	class BorderColorPerEdgeExample < Phlex::TUI
		def view_template
			box(
				width: 5,
				height: 4,
				border: :thin,
				border_color: { top: :red, right: :green, bottom: :blue, left: :yellow }
			)
		end
	end

	test "paragraph and span color attributes paint text colors" do
		renderer = Phlex::TUI::Render.new(InlineColorExample.new.call, width: :fit, height: :fit)
		renderer.call

		assert_equal renderer.canvas.cell_character(0, 0), "A"
		assert_equal renderer.canvas.cell_color(0, 0), Phlex::TUI::Terminal.color(:red)
		assert_equal renderer.canvas.cell_bg(0, 0), Phlex::TUI::Terminal.color(:blue)
	end

	test "span color inheritance follows parent, with explicit override" do
		renderer = Phlex::TUI::Render.new(InheritedColorExample.new.call, width: :fit, height: :fit)
		renderer.call

		assert_equal renderer.canvas.cell_character(0, 0), "A"
		assert_equal renderer.canvas.cell_color(0, 0), Phlex::TUI::Terminal.color(:yellow)
		assert_equal renderer.canvas.cell_character(0, 1), "B"
		assert_equal renderer.canvas.cell_color(0, 1), Phlex::TUI::Terminal.color(:cyan)
	end

	test "box supports per-edge border colors" do
		renderer = Phlex::TUI::Render.new(BorderColorPerEdgeExample.new.call, width: :fit, height: :fit)
		renderer.call

		assert_equal renderer.canvas.cell_color(0, 2), Phlex::TUI::Terminal.color(:red)
		assert_equal renderer.canvas.cell_color(1, 4), Phlex::TUI::Terminal.color(:green)
		assert_equal renderer.canvas.cell_color(3, 2), Phlex::TUI::Terminal.color(:blue)
		assert_equal renderer.canvas.cell_color(1, 0), Phlex::TUI::Terminal.color(:yellow)

		assert_equal renderer.canvas.cell_color(0, 0), Phlex::TUI::Terminal.color(:red)
		assert_equal renderer.canvas.cell_color(0, 4), Phlex::TUI::Terminal.color(:red)
		assert_equal renderer.canvas.cell_color(3, 0), Phlex::TUI::Terminal.color(:blue)
		assert_equal renderer.canvas.cell_color(3, 4), Phlex::TUI::Terminal.color(:blue)
	end
end
