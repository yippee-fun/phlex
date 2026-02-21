# frozen_string_literal: true

class Phlex::TUI::CanvasSurface
	def initialize(canvas:, origin_row:, origin_col:, width:, height:)
		@canvas = canvas
		@origin_row = origin_row
		@origin_col = origin_col
		@width = width
		@height = height
	end

	attr_reader :width
	attr_reader :height

	def text(row:, col:, text:, **styles)
		@canvas.paint_text(row: @origin_row + row, col: @origin_col + col, text:, **styles)
	end

	def blit_rows(row:, col:, rows:, limit: nil, **styles)
		@canvas.paint_rows(row: @origin_row + row, col: @origin_col + col, rows:, limit:, **styles)
	end

	def box(row:, col:, width:, height:, border: nil, border_color: nil, bg: nil)
		@canvas.paint_box(row: @origin_row + row, col: @origin_col + col, width:, height:, border:, border_color:, bg:)
	end

	def hline(row:, col:, width:, style: :thin, color: nil)
		@canvas.draw_horizontal_line(row: @origin_row + row, col: @origin_col + col, width:, style:, color:)
	end

	def vline(row:, col:, height:, style: :thin, color: nil)
		@canvas.draw_vertical_line(row: @origin_row + row, col: @origin_col + col, height:, style:, color:)
	end

	def cell(row:, col:, character:, **styles)
		text(row:, col:, text: character.to_s, **styles)
	end

	def with_clip(row:, col:, width:, height:)
		@canvas.with_clip(row: @origin_row + row, col: @origin_col + col, width:, height:) do
			yield self
		end
	end
end
