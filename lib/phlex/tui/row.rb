# frozen_string_literal: true

class Phlex::TUI::Row < Phlex::TUI::Box
	def initialize(*, direction: :horizontal, border_mode: :collapse, **)
		super
	end

	def fit_width(_renderer)
		validate_row_structure!
		super
	end

	def fit_height(_renderer)
		validate_row_structure!
		super
	end

	def collapse_top_edge
		max_child_edge = 0

		each_flow_children do |child|
			edge = child.collapse_top_edge
			max_child_edge = edge if edge > max_child_edge
		end

		[super, max_child_edge].max
	end

	def collapse_bottom_edge
		max_child_edge = 0

		each_flow_children do |child|
			edge = child.collapse_bottom_edge
			max_child_edge = edge if edge > max_child_edge
		end

		[super, max_child_edge].max
	end

	private def validate_row_structure!
		each_flow_children do |child|
			next if Phlex::TUI::Col === child

			raise ArgumentError, "Rows can only contain columns"
		end
	end
end
