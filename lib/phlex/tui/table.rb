# frozen_string_literal: true

class Phlex::TUI::Table < Phlex::TUI::Box
	TrackPlacement = Data.define(:column, :start, :colspan)
	TableGrid = Data.define(:rows, :column_count, :placements_by_row)

	def initialize(*, direction: :vertical, border_mode: :collapse, **)
		super
	end

	def normalize_table_widths(_renderer)
		grid = build_table_grid!
		return if grid.rows.empty? || grid.column_count.zero?

		target_widths = Array.new(grid.column_count, 0)
		track_max_widths = Array.new(grid.column_count, Float::INFINITY)

		seed_single_column_tracks!(target_widths, track_max_widths, grid)
		satisfy_spanned_min_widths!(target_widths, grid)

		table_target_width = clamp(width - inset_horizontal, min_width - inset_horizontal, max_width - inset_horizontal)
		remaining_width = [table_target_width - target_widths.sum, 0].max
		distribute_remaining_track_width!(target_widths, track_max_widths, remaining_width)
		apply_track_widths_to_rows!(target_widths, grid)

		self.width = [width, inset_horizontal + width_of_child_nodes].max
		self.min_width = [min_width, width, inset_horizontal + min_width_of_child_nodes].max
	end

	def normalize_table_heights(_renderer)
		build_table_grid!

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

	private def build_table_grid!
		rows = each_flow_children.to_a
		validate_table_child_types!(rows)

		column_count = nil
		rows.each_with_index do |row, row_index|
			row_column_count = row.each_flow_children.sum(&:colspan)

			column_count ||= row_column_count
			next if row_column_count == column_count

			raise ArgumentError,
				"Row #{row_index + 1} has total colspan #{row_column_count}, expected #{column_count}"
		end

		column_count ||= 0
		placements_by_row = {}

		rows.each_with_index do |row, row_index|
			placements_by_row[row] = build_row_tracks(row, column_count, row_index)
		end

		TableGrid.new(rows:, column_count:, placements_by_row:)
	end

	private def validate_table_child_types!(rows)
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
	end

	private def build_row_tracks(row, column_count, row_index)
		placements = []
		cursor = 0

		row.each_flow_children.with_index do |column, column_index|
			colspan = column.colspan

			unless Integer === colspan && colspan >= 1
				raise ArgumentError,
					"Row #{row_index + 1}, column #{column_index + 1} has invalid colspan #{colspan.inspect}"
			end

			if cursor + colspan > column_count
				raise ArgumentError,
					"Row #{row_index + 1}, column #{column_index + 1} overflows table width #{column_count} with colspan #{colspan}"
			end

			placements << TrackPlacement.new(column:, start: cursor, colspan:)
			cursor += colspan
		end

		placements
	end

	private def seed_single_column_tracks!(target_widths, track_max_widths, grid)
		grid.rows.each do |row|
			grid.placements_by_row.fetch(row).each do |placement|
				next unless placement.colspan == 1

				track = placement.start
				column = placement.column
				target_widths[track] = [target_widths[track], column.width].max
				track_max_widths[track] = [track_max_widths[track], column.max_width].min
			end
		end
	end

	private def apply_track_widths_to_rows!(target_widths, grid)
		grid.rows.each do |row|
			grid.placements_by_row.fetch(row).each do |placement|
				target = target_widths.slice(placement.start, placement.colspan).sum
				column = placement.column
				column.width = target
				column.min_width = [column.min_width, target].max
				column.max_width = [column.max_width, target].max
			end

			row_target_width = clamp(width - inset_horizontal, row.min_width, row.max_width)
			row.width = [row.width, row_target_width, row.inset_horizontal + row.width_of_child_nodes].max
			row.min_width = [row.min_width, row.width, row.inset_horizontal + row.min_width_of_child_nodes].max
		end
	end

	private def satisfy_spanned_min_widths!(target_widths, grid)
		changed = true

		while changed
			changed = false

			grid.rows.each do |row|
				grid.placements_by_row.fetch(row).each do |placement|
					next if placement.colspan == 1

					current_width = target_widths.slice(placement.start, placement.colspan).sum
					next unless placement.column.width > current_width

					extra_width = placement.column.width - current_width
					distribute_extra_width!(target_widths, placement.start, placement.colspan, extra_width)
					changed = true
				end
			end
		end
	end

	private def distribute_remaining_track_width!(target_widths, track_max_widths, remaining_width)
		growable_indexes = target_widths.each_index.select { |index| target_widths[index] < track_max_widths[index] }

		while remaining_width > 0 && growable_indexes.any?
			growable_indexes.sort_by! { |index| target_widths[index] }

			current_width = target_widths[growable_indexes.first]
			group = growable_indexes.take_while { |index| target_widths[index] == current_width }
			next_width_index = growable_indexes[group.size]
			next_group_width = next_width_index ? target_widths[next_width_index] : Float::INFINITY
			target_width = group.map { |index| track_max_widths[index] }.min
			target_width = [target_width, next_group_width].min

			gap = target_width - current_width
			if gap <= 0
				growable_indexes.reject! { |index| target_widths[index] >= track_max_widths[index] }
				next
			end

			group_growth_budget = [gap * group.size, remaining_width].min
			evenly_distributed(group_growth_budget, group.size).each_with_index do |budgeted_growth, offset|
				index = group[offset]
				growth = [budgeted_growth, track_max_widths[index] - target_widths[index]].min
				target_widths[index] += growth
				remaining_width -= growth
			end

			growable_indexes.reject! { |index| target_widths[index] >= track_max_widths[index] }
		end
	end

	private def distribute_extra_width!(target_widths, start, colspan, extra_width)
		evenly_distributed(extra_width, colspan).each_with_index do |width, offset|
			target_widths[start + offset] += width
		end
	end

	private def evenly_distributed(total, parts)
		base, remainder = total.divmod(parts)

		Array.new(parts) do |index|
			base + ((index < remainder) ? 1 : 0)
		end
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end
end
