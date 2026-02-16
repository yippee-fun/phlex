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

	class ColspanExample < Phlex::TUI
		def view_template
			table(width: :grow, border: :rounded) do
				row do
					col(border: :rounded, colspan: 2) { "Wide" }
				end

				row do
					col(border: :rounded) { "Left" }
					col(border: :rounded) { "Right" }
				end
			end
		end
	end

	class InvalidColspanExample < Phlex::TUI
		def view_template
			table do
				row do
					col(colspan: 2) { "a" }
				end

				row do
					col { "b" }
				end
			end
		end
	end

	class ColspanWidthInvariantExample < Phlex::TUI
		def view_template
			table(width: :grow) do
				row do
					col { "a" }
					col { "b" }
				end

				row do
					col(colspan: 2) { "wide" }
				end
			end
		end
	end

	test "table width grow expands row columns" do
		tree = Example.new.call
		renderer = Phlex::TUI::Render.new(tree, width: 20, height: 5)

		output = renderer.call.gsub(/\e\[[\d;]*m/, "")
		lines = output.lines(chomp: true)

		assert_equal lines[1], "│╭───────┬───────╮ │"
		assert_equal lines[2], "││a      │b      │ │"
	end

	test "colspan tracks align with regular columns" do
		tree = ColspanExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: 30, height: 8)
		renderer.call

		table = tree.root.children.first
		rows = table.each_flow_children.to_a
		first_row_columns = rows[0].each_flow_children.to_a
		second_row_columns = rows[1].each_flow_children.to_a

		assert_equal 2, first_row_columns.first.colspan
		assert_equal first_row_columns.first.width, second_row_columns.sum(&:width)
	end

	test "table rows must have matching total colspan" do
		tree = InvalidColspanExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: 20, height: 6)

		error = assert_raises(ArgumentError) { renderer.call }
		assert_equal "Row 2 has total colspan 1, expected 2", error.message
	end

	test "colspan rejects values less than one" do
		error = assert_raises(ArgumentError) do
			Class.new(Phlex::TUI) do
				def view_template
					table do
						row do
							col(colspan: 0) { "bad" }
						end
					end
				end
			end.new.call
		end

		assert_equal "colspan must be an Integer >= 1", error.message
	end

	test "track widths fill table content width for unbordered columns" do
		tree = ColspanWidthInvariantExample.new.call
		renderer = Phlex::TUI::Render.new(tree, width: 20, height: 6)
		renderer.call

		table = tree.root.children.first
		rows = table.each_flow_children.to_a
		first_row_columns = rows[0].each_flow_children.to_a
		second_row_span = rows[1].each_flow_children.first

		assert_equal table.width - table.inset_horizontal, first_row_columns.sum(&:width)
		assert_equal first_row_columns.sum(&:width), second_row_span.width
	end
end
