# frozen_string_literal: true

class TUICanvasNodeTest < Quickdraw::Test
	class ConstrainedCanvasExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			box(width: 12, height: 4) do
				canvas(width: :grow, height: :grow) do |surface, width, height|
					@calls << [width, height]
					surface.text(row: 0, col: 0, text: "ok")
				end
			end
		end
	end

	class FitCanvasExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			canvas(width: :fit, height: :fit, measure: method(:measure)) do |surface, _width, _height|
				surface.text(row: 0, col: 0, text: "ab")
				surface.text(row: 1, col: 0, text: "cde")
			end
		end

		private def measure(width, height)
			@calls << [width, height]
			[3, 2]
		end
	end

	class ClipCanvasExample < Phlex::TUI
		def view_template
			canvas(width: 5, height: 2) do |surface|
				surface.text(row: 0, col: 0, text: "abcdef")
				surface.text(row: 1, col: 0, text: "x")
			end
		end
	end

	test "constrained canvas receives allocated size" do
		calls = []
		renderer = Phlex::TUI::Render.new(ConstrainedCanvasExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert_equal [[12, 4]], calls
	end

	test "fit canvas contributes intrinsic size" do
		calls = []
		renderer = Phlex::TUI::Render.new(FitCanvasExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert_equal 3, renderer.width
		assert_equal 2, renderer.height
		assert calls.include?([nil, nil])
	end

	test "canvas output is clipped and padded to allocated area" do
		renderer = Phlex::TUI::Render.new(ClipCanvasExample.new.call, width: :fit, height: :fit)
		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal "abcde\nx    ", output
	end
end
