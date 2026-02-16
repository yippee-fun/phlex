# frozen_string_literal: true

class TUIEmbedTest < Quickdraw::Test
	class ConstrainedEmbedExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			box(width: 12, height: 4) do
				embed(width: :grow, height: :grow) do |width, height|
					@calls << [width, height]
					"ok"
				end
			end
		end
	end

	class GrowEmbedMinSizeExample < Phlex::TUI
		def view_template
			embed(width: :grow, height: :grow, min_width: 5, min_height: 2) do |_width, _height|
				"ignored"
			end
		end
	end

	class FitEmbedExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			embed(width: :fit, height: :fit) do |width, height|
				@calls << [width, height]
				"ab\ncde"
			end
		end
	end

	class PartialFitEmbedExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			embed(width: :fit, height: 8) do |width, height|
				@calls << [width, height]
				"x"
			end
		end
	end

	class ClipPadEmbedExample < Phlex::TUI
		def view_template
			embed(width: 5, height: 3) do |width, height|
				"#{width}x#{height}\nabcdef\nx"
			end
		end
	end

	class AnsiEmbedExample < Phlex::TUI
		def view_template
			embed(width: 3, height: 1) do |width, height|
				next "" unless width && height

				"\e[31mA\e[2K\e[0mB"
			end
		end
	end

	class SingleArgumentEmbedExample < Phlex::TUI
		def view_template
			embed(width: 4, height: 1) do |width|
				"w#{width}"
			end
		end
	end

	class CachedFitEmbedExample < Phlex::TUI
		def initialize(calls:)
			@calls = calls
		end

		def view_template
			embed(width: :fit, height: :fit) do |width, height|
				@calls << [width, height]
				"hello"
			end
		end
	end

	test "constrained embed receives allocated size" do
		calls = []
		renderer = Phlex::TUI::Render.new(ConstrainedEmbedExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert_equal 1, calls.length
		assert_equal [12, 4], calls.last
	end

	test "fit embed contributes intrinsic size" do
		calls = []
		renderer = Phlex::TUI::Render.new(FitEmbedExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert_equal 3, renderer.width
		assert_equal 2, renderer.height
		assert_equal [[nil, nil], [3, nil]], calls
	end

	test "grow embed starts from min size in fit canvas" do
		renderer = Phlex::TUI::Render.new(GrowEmbedMinSizeExample.new.call, width: :fit, height: :fit)
		renderer.call

		assert_equal 5, renderer.width
		assert_equal 2, renderer.height
	end

	test "partial fit passes nil for unresolved axis" do
		calls = []
		renderer = Phlex::TUI::Render.new(PartialFitEmbedExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert calls.include?([nil, 8])
		assert_equal [1, 8], calls.last
	end

	test "embed output is clipped and padded to allocated area" do
		renderer = Phlex::TUI::Render.new(ClipPadEmbedExample.new.call, width: :fit, height: :fit)
		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal "5x3  \nabcde\nx    ", output
	end

	test "embed parses sgr styles and ignores unsupported controls" do
		renderer = Phlex::TUI::Render.new(AnsiEmbedExample.new.call, width: :fit, height: :fit)
		renderer.call

		assert_equal "A", renderer.canvas.cell_character(0, 0)
		assert_equal Phlex::TUI::Terminal.color(:red), renderer.canvas.cell_color(0, 0)
		assert_equal "B", renderer.canvas.cell_character(0, 1)
		assert_equal Phlex::TUI::Terminal.color(:foreground), renderer.canvas.cell_color(0, 1)
		assert_equal " ", renderer.canvas.cell_character(0, 2)
	end

	test "embed allows blocks that accept only width" do
		renderer = Phlex::TUI::Render.new(SingleArgumentEmbedExample.new.call, width: :fit, height: :fit)
		output = renderer.call.gsub(/\e\[[\d;]*m/, "")

		assert_equal "w4  ", output
	end

	test "embed reuses cached content within a render" do
		calls = []
		renderer = Phlex::TUI::Render.new(CachedFitEmbedExample.new(calls:).call, width: :fit, height: :fit)
		renderer.call

		assert_equal [[nil, nil], [5, nil]], calls
	end
end
