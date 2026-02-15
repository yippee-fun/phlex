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

	test "paragraph and span color attributes paint text colors" do
		renderer = Phlex::TUI::Render.new(InlineColorExample.new.call, width: :fit, height: :fit)
		renderer.call

		cell = renderer.canvas.raw_cell(0, 0)

		assert_equal cell.character, "A"
		assert_equal cell.color, Phlex::TUI::Terminal.color(:red)
		assert_equal cell.bg, Phlex::TUI::Terminal.color(:blue)
	end

	test "span color inheritance follows parent, with explicit override" do
		renderer = Phlex::TUI::Render.new(InheritedColorExample.new.call, width: :fit, height: :fit)
		renderer.call

		first = renderer.canvas.raw_cell(0, 0)
		second = renderer.canvas.raw_cell(0, 1)

		assert_equal first.character, "A"
		assert_equal first.color, Phlex::TUI::Terminal.color(:yellow)
		assert_equal second.character, "B"
		assert_equal second.color, Phlex::TUI::Terminal.color(:cyan)
	end
end
