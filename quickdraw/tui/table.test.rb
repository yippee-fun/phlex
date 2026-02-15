# frozen_string_literal: true

class TUITableTest < Quickdraw::Test
	class Example < Phlex::TUI
		def view_template
			table(width: :grow, border: :rounded) do
				row do
					col(border: :rounded) { "a" }
					col(border: :rounded) { "b" }
				end
			end
		end
	end

	test "table width grow expands row columns" do
		tree = Example.new.call
		renderer = Phlex::TUI::Render.new(tree, width: 20, height: 5)

		output = renderer.call.gsub(/\e\[[\d;]*m/, "")
		lines = output.lines(chomp: true)

		assert_equal lines[1], "│╭────────┬───────╮│"
		assert_equal lines[2], "││a       │b      ││"
	end
end
