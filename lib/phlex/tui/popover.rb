# frozen_string_literal: true

class Phlex::TUI::Popover < Phlex::TUI::Box
	ANCHORS = [:canvas, :parent].freeze
	VERTICAL_SIDES = [:top, :middle, :bottom].freeze
	HORIZONTAL_SIDES = [:left, :center, :right].freeze

	def initialize(anchor: :canvas, top: nil, middle: nil, bottom: nil, left: nil, center: nil, right: nil, z: 0, **)
		super(**)
		@base_max_width = max_width
		@base_max_height = max_height

		@anchor = validate_anchor(anchor)
		@z = validate_z(z)
		@vertical_constraints = normalize_constraints(
			top:,
			middle:,
			bottom:,
			valid_sides: VERTICAL_SIDES,
			axis_name: :vertical
		)
		@horizontal_constraints = normalize_constraints(
			left:,
			center:,
			right:,
			valid_sides: HORIZONTAL_SIDES,
			axis_name: :horizontal
		)
	end

	attr_reader :anchor
	attr_reader :z

	def popover?
		true
	end

	def fit_width(renderer)
		super
		resolve_width!(renderer)
	end

	def grow_width(renderer)
		resolve_width!(renderer)
		super
	end

	def fit_height(renderer)
		super
		resolve_height!(renderer)
	end

	def grow_height(renderer)
		resolve_height!(renderer)
		super
	end

	def position(renderer)
		resolve_position!(renderer)
		super
	end

	private def resolve_width!(renderer)
		effective_max_width = canvas_limited_max_width(renderer)
		effective_min_width = [min_width, effective_max_width].min

		if Integer === requested_width
			self.width = clamp(width, effective_min_width, effective_max_width)
			return
		end

		if @horizontal_constraints[:left] && @horizontal_constraints[:right]
			self.width = clamp(horizontal_span(renderer), effective_min_width, effective_max_width)
			return
		end

		if requested_width == :grow
			self.width = clamp(renderer.width, effective_min_width, effective_max_width)
		else
			self.width = clamp(width, effective_min_width, effective_max_width)
		end
	end

	private def resolve_height!(renderer)
		effective_max_height = canvas_limited_max_height(renderer)
		effective_min_height = [min_height, effective_max_height].min

		if Integer === requested_height
			self.height = clamp(height, effective_min_height, effective_max_height)
			return
		end

		if @vertical_constraints[:top] && @vertical_constraints[:bottom]
			self.height = clamp(vertical_span(renderer), effective_min_height, effective_max_height)
			return
		end

		if requested_height == :grow
			self.height = clamp(renderer.height, effective_min_height, effective_max_height)
		else
			self.height = clamp(height, effective_min_height, effective_max_height)
		end
	end

	private def resolve_position!(renderer)
		frame_row, frame_col, frame_height, frame_width = positioning_frame(renderer)

		vertical = default_constraints(@vertical_constraints, :middle)

		horizontal = default_constraints(@horizontal_constraints, :center)

		my_vertical_side, vertical_constraint = preferred_constraint(vertical, :top, :bottom, :middle)
		my_horizontal_side, horizontal_constraint = preferred_constraint(horizontal, :left, :right, :center)

		self.row = solve_axis_start(
			frame_row,
			frame_height,
			height,
			my_vertical_side,
			vertical_constraint[:anchor_side],
			vertical_constraint[:offset]
		)

		self.col = solve_axis_start(
			frame_col,
			frame_width,
			width,
			my_horizontal_side,
			horizontal_constraint[:anchor_side],
			horizontal_constraint[:offset]
		)
	end

	private def positioning_frame(renderer)
		if anchor == :parent && parent
			[parent.row, parent.col, parent.height, parent.width]
		else
			[0, 0, renderer.height, renderer.width]
		end
	end

	private def horizontal_span(renderer)
		_frame_row, frame_col, _frame_height, frame_width = positioning_frame(renderer)
		left = @horizontal_constraints[:left]
		right = @horizontal_constraints[:right]

		left_position = anchor_position(frame_col, frame_width, left[:anchor_side]) + left[:offset]
		right_position = anchor_position(frame_col, frame_width, right[:anchor_side]) + right[:offset]

		[right_position - left_position, 0].max
	end

	private def vertical_span(renderer)
		frame_row, _frame_col, frame_height, _frame_width = positioning_frame(renderer)
		top = @vertical_constraints[:top]
		bottom = @vertical_constraints[:bottom]

		top_position = anchor_position(frame_row, frame_height, top[:anchor_side]) + top[:offset]
		bottom_position = anchor_position(frame_row, frame_height, bottom[:anchor_side]) + bottom[:offset]

		[bottom_position - top_position, 0].max
	end

	private def solve_axis_start(frame_start, frame_size, node_size, my_side, anchor_side, offset)
		anchor = anchor_position(frame_start, frame_size, anchor_side)
		self_side = side_offset(my_side, node_size)
		(anchor + offset - self_side).floor
	end

	private def anchor_position(frame_start, frame_size, side)
		frame_start + side_offset(side, frame_size)
	end

	private def side_offset(side, size)
		case side
		in :top | :left
			0
		in :middle | :center
			size / 2.0
		in :bottom | :right
			size
		end
	end

	private def preferred_constraint(constraints, first, second, fallback)
		if constraints[first]
			[first, constraints[first]]
		elsif constraints[second]
			[second, constraints[second]]
		else
			[fallback, constraints[fallback]]
		end
	end

	private def normalize_constraints(top: nil, middle: nil, bottom: nil, left: nil, center: nil, right: nil, valid_sides:, axis_name:)
		values = {
			top:,
			middle:,
			bottom:,
			left:,
			center:,
			right:,
		}

		constraints = {}

		valid_sides.each do |side|
			value = values[side]
			next if value.nil?

			constraints[side] = normalize_constraint(side, value, valid_sides)
		end

		validate_constraint_combination!(axis_name, constraints.keys)
		constraints
	end

	private def normalize_constraint(my_side, value, valid_sides)
		anchor_side, offset = case value
		in Integer
			[my_side, value]
		in Hash => hash
			if hash.size != 1
				raise ArgumentError, "#{my_side.inspect} must contain exactly one anchor side"
			end

			pair = hash.first
			unless pair
				raise ArgumentError, "#{my_side.inspect} must contain exactly one anchor side"
			end

			pair
		else
			raise ArgumentError, "#{my_side.inspect} must be an Integer offset or a single-key Hash"
		end

		unless valid_sides.include?(anchor_side)
			raise ArgumentError, "#{my_side.inspect} can only anchor to #{valid_sides.map(&:inspect).join(', ')}"
		end

		unless Integer === offset
			raise ArgumentError, "#{my_side.inspect} offset must be an Integer"
		end

		offset = normalize_offset(my_side, offset)

		{ anchor_side:, offset: }
	end

	private def normalize_offset(side, offset)
		case side
		in :right | :bottom
			-offset
		else
			offset
		end
	end

	private def validate_constraint_combination!(axis_name, keys)
		return if keys.size <= 1

		if axis_name == :horizontal
			return if keys.sort == [:left, :right]
		else
			return if keys.sort == [:bottom, :top]
		end

		raise ArgumentError, "Invalid #{axis_name} constraints: #{keys.inspect}"
	end

	private def validate_anchor(anchor)
		return anchor if ANCHORS.include?(anchor)

		raise ArgumentError, "Unknown anchor: #{anchor.inspect}"
	end

	private def validate_z(z)
		return z if Integer === z

		raise ArgumentError, "z must be an Integer"
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end

	private def default_constraints(constraints, fallback)
		return constraints unless constraints.empty?

		{ fallback => { anchor_side: fallback, offset: 0 } }
	end

	private def canvas_limited_max_width(renderer)
		[@base_max_width, renderer.width].min
	end

	private def canvas_limited_max_height(renderer)
		[@base_max_height, renderer.height].min
	end
end
