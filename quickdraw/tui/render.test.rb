# frozen_string_literal: true

class TUIRenderTest < Quickdraw::Test
	class Example < Phlex::TUI
		def view_template
			paragraph("AB")

			popover(anchor: :canvas, right: 0, bottom: 0) do
				paragraph("P")
			end
		end
	end

	class HorizontalGrowHeightExample < Phlex::TUI
		def view_template
			hstack do
				box(border: :rounded, height: :grow) { "A" }
				box(border: :rounded) { "B\nC" }
			end
		end
	end

	class OverflowNoneExample < Phlex::TUI
		def view_template
			box(width: 10, height: 5, border: :thin, overflow: :none) do
				box(width: :grow, height: :fit, padding: { top: -1 }) do
					paragraph("HELLO")
				end
			end
		end
	end

	class OverflowBorderExample < Phlex::TUI
		def view_template
			box(width: 10, height: 5, border: :thin, overflow: :border) do
				box(width: :grow, height: :fit, padding: { top: -1 }) do
					paragraph("HELLO")
				end
			end
		end
	end

	test "fit canvas uses resolved canvas for canvas-anchored popovers" do
		tree = Example.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal output, "AP"
		assert_equal renderer.width, 2
		assert_equal renderer.height, 1
	end

	test "horizontal grow-height children stretch to parent content height" do
		tree = HorizontalGrowHeightExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)
		renderer.call

		row = tree.root.children.first
		left_box, right_box = row.each_flow_children.to_a

		assert_equal 4, right_box.height
		assert_equal right_box.height, left_box.height
	end

	test "overflow none clips children before border" do
		tree = OverflowNoneExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		lines = renderer.call.gsub(/\e\[[\d;]*m/, "").split("\n")

		assert_equal "┌────────┐", lines.first
		assert_equal true, lines[1].include?("HELLO")
	end

	test "overflow border allows children to draw on border" do
		tree = OverflowBorderExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		lines = renderer.call.gsub(/\e\[[\d;]*m/, "").split("\n")

		assert_equal true, lines.first.include?("HELLO")
	end
end
