# frozen_string_literal: true

class Phlex::Tux::Table < Phlex::TUI
	Column = Data.define(:header, :block)

	def initialize(data)
		@data = data
		@columns = []
	end

	def view_template
		yield(self)

		table do
			row(bold: true) do
				@columns.each do |column|
					col(border: :rounded, padding: [0, 1]) do
						column.header
					end
				end
			end

			@data.each do |row|
				row do
					@columns.each do |column|
						col(border: :rounded, padding: [0, 1]) do
							column.block.call(row)
						end
					end
				end
			end
		end
	end

	def column(header, &block)
		@columns << Column.new(header:, block:)
	end
end
