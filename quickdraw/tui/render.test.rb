# frozen_string_literal: true

class TUIRenderTest < Quickdraw::Test
	class Example < Phlex::TUI
		def view_template
			paragraph("AB")

			popover(anchor: :viewport, right: 0, bottom: 0) do
				paragraph("P")
			end
		end
	end

	test "fit canvas uses resolved viewport for viewport-anchored popovers" do
		tree = Example.new.call
		renderer = Phlex::TUI::Render.new(tree, width: :fit, height: :fit)

		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal output, "AP"
		assert_equal renderer.width, 2
		assert_equal renderer.height, 1
	end
end
