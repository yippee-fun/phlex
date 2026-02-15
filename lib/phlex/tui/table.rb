# frozen_string_literal: true

class Phlex::TUI::Table < Phlex::TUI::Box
	def initialize(*, direction: :vertical, border_mode: :collapse, **)
		super
	end

	def normalize_table_widths(_renderer)
		validate_table_structure!

		rows = each_flow_children.to_a
		return if rows.empty?

		column_count = rows.first.each_flow_children.count
		return if column_count.zero?

		target_widths = Array.new(column_count, 0)

		rows.each do |row|
			row.each_flow_children.with_index do |col, index|
				target_widths[index] = [target_widths[index], col.width].max
			end
		end

		rows.each do |row|
			row.each_flow_children.with_index do |col, index|
				target = target_widths[index]
				col.width = target
				col.min_width = [col.min_width, target].max
				col.max_width = [col.max_width, target].max
			end

			row_target_width = clamp(width - inset_horizontal, row.min_width, row.max_width)
			available_child_width = [row_target_width - row.inset_horizontal - row.width_of_child_nodes, 0].max
			grow_columns!(row.each_flow_children.to_a, available_child_width)

			row.width = [row.width, row_target_width, row.inset_horizontal + row.width_of_child_nodes].max
			row.min_width = [row.min_width, row.width, row.inset_horizontal + row.min_width_of_child_nodes].max
		end

		self.width = [width, inset_horizontal + width_of_child_nodes].max
		self.min_width = [min_width, width, inset_horizontal + min_width_of_child_nodes].max
	end

	def normalize_table_heights(_renderer)
		validate_table_structure!

		each_flow_children do |row|
			target_height = 0

			row.each_flow_children do |col|
				target_height = col.height if col.height > target_height
			end

			row.each_flow_children do |col|
				col.height = target_height
				col.min_height = [col.min_height, target_height].max
				col.max_height = [col.max_height, target_height].max
			end

			row.height = row.inset_vertical + row.height_of_child_nodes
			row.min_height = [row.min_height, row.inset_vertical + row.min_height_of_child_nodes].max
		end

		self.height = inset_vertical + height_of_child_nodes
		self.min_height = [min_height, inset_vertical + min_height_of_child_nodes].max
	end

	private def validate_table_structure!
		rows = each_flow_children.to_a

		rows.each do |child|
			next if Phlex::TUI::Row === child

			raise ArgumentError, "Tables can only contain rows"
		end

		rows.each do |row|
			row.each_flow_children do |child|
				next if Phlex::TUI::Col === child

				raise ArgumentError, "Rows can only contain columns"
			end
		end

		column_count = rows.first&.each_flow_children&.count
		return unless column_count

		rows.each do |row|
			next if row.each_flow_children.count == column_count

			raise ArgumentError, "All rows in a table must have the same number of columns"
		end
	end

	private def grow_columns!(columns, remaining_width)
		growables = columns.select { |column| column.width < column.max_width }

		while remaining_width > 0 && growables.any?
			growables.sort_by!(&:width)

			current_width = growables.first.width
			group = growables.take_while { |column| column.width == current_width }
			target_width = growables[group.size]&.width || Float::INFINITY

			gap = target_width - current_width
			share = [gap, remaining_width / group.size].min
			remainder = [gap * group.size, remaining_width].min - (share * group.size)

			group.each do |column|
				extra = (remainder > 0) ? 1 : 0
				growth = [share + extra, column.max_width - column.width].min
				column.width += growth
				column.min_width = [column.min_width, column.width].max
				remaining_width -= growth
				remainder -= extra
			end

			growables.reject! { |column| column.width >= column.max_width }
		end
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end
end
