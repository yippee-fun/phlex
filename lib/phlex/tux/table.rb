# frozen_string_literal: true

class Phlex::Tux::Table < Phlex::TUI
	Column = Data.define(:header, :block, :text_align)

	def initialize(data)
		@data = data
		@columns = []
	end

	def view_template
		yield(self)

		table(width: :grow) do
			row(bold: true, bg: :red) do
				@columns.each do |column|
					col(border: :rounded, padding: [0, 1]) do
						column.header
					end
				end
			end

			@data.each do |row|
				row do
					@columns.each do |column|
						col(text_align: column.text_align, border: :rounded, padding: [0, 1]) do
							column.block.call(row)
						end
					end
				end
			end
		end
	end

	def column(header, text_align: :left, &block)
		@columns << Column.new(header:, block:, text_align:)
	end
end
