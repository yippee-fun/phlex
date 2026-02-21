# frozen_string_literal: true

class TUICompiledFontTest < Quickdraw::Test
	test "builds glyph metrics and fallback" do
		font = Phlex::TUI::CompiledFont.new({
			"A" => ["▄", "█"],
			" " => [" ", " "],
			"?" => ["█", "█"],
		})

		assert_equal 2, font.row_count
		assert_equal 1, font.space_width

		glyph = font.glyph_for("A")
		assert_equal 1, glyph.width
		assert_equal ["▄", "█"], glyph.rows
		assert_equal [[1], [3]], glyph.masks

		fallback = font.glyph_for("Z")
		assert_equal ["█", "█"], fallback.rows
	end

	test "validates row count consistency" do
		error = assert_raises(ArgumentError) do
			Phlex::TUI::CompiledFont.new({
				"A" => ["█", "█"],
				"B" => ["█"],
			})
		end

		assert_equal "all glyphs must have the same row count", error.message
	end
end
