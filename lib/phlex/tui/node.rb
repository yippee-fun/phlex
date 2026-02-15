# frozen_string_literal: true

class Phlex::TUI::Node
	EMPTY_ARRAY = [].freeze

	attr_accessor :row
	attr_accessor :col
	attr_accessor :width
	attr_accessor :height
	attr_accessor :min_width
	attr_accessor :min_height
	attr_accessor :max_width
	attr_accessor :max_height

	def fit_width(...)
	end

	def grow_width(...)
	end

	def normalize_table_widths(...)
	end

	def wrap_text(...)
	end

	def fit_height(...)
	end

	def grow_height(...)
	end

	def normalize_table_heights(...)
	end

	def position(...)
	end

	def draw(...)
	end

	def children
		EMPTY_ARRAY
	end

	def each_flow_children
		return enum_for(__method__) unless block_given?

		children.each { |child| yield child }
	end

	def popover?
		false
	end

	def z
		0
	end

	def border_top_width
		0
	end

	def border_right_width
		0
	end

	def border_bottom_width
		0
	end

	def border_left_width
		0
	end

	def collapse_top_edge
		border_top_width
	end

	def collapse_right_edge
		border_right_width
	end

	def collapse_bottom_edge
		border_bottom_width
	end

	def collapse_left_edge
		border_left_width
	end

	protected def initialize_geometry(width:, height:, min_width:, min_height:, max_width:, max_height:)
		@row = 0
		@col = 0
		@width = width
		@height = height
		@min_width = min_width
		@min_height = min_height
		@max_width = max_width
		@max_height = max_height
	end
end
