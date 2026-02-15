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
			row.each_flow_children.each_with_index do |col, index|
				target_widths[index] = [target_widths[index], col.width].max
			end
		end

		rows.each do |row|
			row.each_flow_children.each_with_index do |col, index|
				target = target_widths[index]
				col.width = target
				col.min_width = [col.min_width, target].max
				col.max_width = [col.max_width, target].max
			end

			row.width = row.inset_horizontal + row.width_of_child_nodes
			row.min_width = [row.min_width, row.inset_horizontal + row.min_width_of_child_nodes].max
		end

		self.width = inset_horizontal + width_of_child_nodes
		self.min_width = [min_width, inset_horizontal + min_width_of_child_nodes].max
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
end
