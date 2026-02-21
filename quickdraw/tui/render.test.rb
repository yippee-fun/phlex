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

	class PreserveTrailingWhitespaceExample < Phlex::TUI
		def view_template
			paragraph("A  ", trim_trailing_whitespace: false)
		end
	end

	class FixedParentGrowChildExample < Phlex::TUI
		def view_template
			box(width: 10, height: 4) do
				box(width: :grow, height: :grow) do
					5.times do |index|
						paragraph("line #{index}")
					end
				end
			end
		end
	end

	class WrappedParagraphExample < Phlex::TUI
		def view_template
			box(width: 8) do
				paragraph("hello world test")
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

	test "overflow none clips children shifted above content" do
		tree = OverflowNoneExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		lines = renderer.call.gsub(/\e\[[\d;]*m/, "").split("\n")

		assert_equal "┌────────┐", lines.first
		assert_equal false, lines.any? { |line| line.include?("HELLO") }
	end

	test "overflow border still clips shifted child content" do
		tree = OverflowBorderExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		lines = renderer.call.gsub(/\e\[[\d;]*m/, "").split("\n")

		assert_equal false, lines.any? { |line| line.include?("HELLO") }
	end

	test "paragraph can preserve trailing whitespace" do
		tree = PreserveTrailingWhitespaceExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal "A  ", output
	end

	test "grow children can shrink inside fixed-size parent" do
		tree = FixedParentGrowChildExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)
		renderer.call

		parent = tree.root.children.first
		child = parent.children.first

		assert_equal 10, parent.width
		assert_equal 4, parent.height
		assert_equal 10, child.width
		assert_equal 4, child.height
	end

	test "wrapped paragraph draws all wrapped lines" do
		tree = WrappedParagraphExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)
		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal "hello   \nworld   \ntest    ", output
	end
end
