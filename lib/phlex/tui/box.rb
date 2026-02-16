# frozen_string_literal: true

class Phlex::TUI::Box < Phlex::TUI::Node
	BORDER_MODES = [:separate, :collapse].freeze

	def initialize(
		align: :left,
		bg: nil,
		color: nil,
		blink: nil,
		bold: nil,
		border: nil,
		border_mode: :separate,
		inverse: nil,
		italic: nil,
		gap: 0,
		height: :fit,
		direction: :vertical,
		strikethrough: nil,
		text_align: :left,
		underline: nil,
		max_height: nil,
		max_width: nil,
		min_height: nil,
		min_width: nil,
		padding: 0,
		parent: nil,
		vertical_align: :top,
		width: :fit
	)
		@parent = parent
		@children = []

		@bg = bg
		@color = (nil == color) ? @parent&.color : color
		@align = align
		@border = Phlex::TUI::Border.parse(border)
		@border_mode = validate_border_mode(border_mode)
		@gap = gap
		@requested_height = height
		@direction = direction
		@text_align = text_align
		@padding = Phlex::TUI::Padding.parse(padding)
		@vertical_align = vertical_align
		@requested_width = width
		@bold = (nil == bold) ? @parent&.bold : bold
		@italic = (nil == italic) ? @parent&.italic : italic
		@underline = (nil == underline) ? @parent&.underline : underline
		@blink = (nil == blink) ? @parent&.blink : blink
		@inverse = (nil == inverse) ? @parent&.inverse : inverse
		@strikethrough = (nil == strikethrough) ? @parent&.strikethrough : strikethrough

		initial_width = (Integer === width) ? width : (min_width || 0)
		initial_height = (Integer === height) ? height : (min_height || 0)

		initialize_geometry(
			width: initial_width,
			height: initial_height,
			min_width: min_width || ((Integer === width) ? width : 0),
			min_height: min_height || ((Integer === height) ? height : 0),
			max_width: max_width || ((Integer === width) ? width : Float::INFINITY),
			max_height: max_height || ((Integer === height) ? height : Float::INFINITY)
		)
	end

	attr_reader :bg
	attr_reader :color
	attr_reader :align
	attr_reader :border
	attr_reader :border_mode
	attr_reader :gap
	attr_reader :requested_width
	attr_reader :requested_height
	attr_reader :parent
	attr_reader :direction
	attr_reader :text_align
	attr_reader :padding
	attr_reader :vertical_align
	attr_reader :children
	attr_reader :bold
	attr_reader :italic
	attr_reader :underline
	attr_reader :blink
	attr_reader :inverse
	attr_reader :strikethrough

	def fit_width(_renderer)
		return unless requested_width in :fit | :grow

		self.min_width = [min_width, inset_horizontal + min_width_of_child_nodes].max
		natural_width = inset_horizontal + width_of_child_nodes
		self.width = clamp(natural_width, min_width, max_width)
	end

	def grow_width(_renderer)
		if direction == :vertical
			target_width = [width - inset_horizontal, 0].max

			each_flow_children do |child|
				next unless child.requested_width == :grow

				child.width = clamp(target_width, child.min_width, child.max_width)
			end
		end

		remaining_width = available_internal_width
		growables = []
		each_flow_children do |child|
			growables << child if child.requested_width == :grow
		end

		while remaining_width > 0 && growables.any?
			growables.sort_by!(&:width)

			current_width = growables.first.width
			group = growables.take_while { |it| it.width == current_width }
			target_width = growables[group.size]&.width || Float::INFINITY

			gap = target_width - current_width
			share = [gap, remaining_width / group.size].min
			remainder = [gap * group.size, remaining_width].min - (share * group.size)

			group.each do |it|
				extra = (remainder > 0) ? 1 : 0
				growth = [share + extra, it.max_width - it.width].min
				it.width += growth
				remaining_width -= growth
				remainder -= extra
			end

			growables.reject! { |it| it.width >= it.max_width }
		end

		overflow_width = -available_internal_width
		shrinkables = []
		each_flow_children do |child|
			shrinkables << child if child.requested_width in :fit | :grow
		end

		while overflow_width > 0 && shrinkables.any?
			shrinkables.sort_by! { |it| -it.width }

			current_width = shrinkables.first.width
			group = shrinkables.take_while { |it| it.width == current_width }
			target_width = shrinkables[group.size]&.width || 0

			gap = current_width - target_width
			share = [gap, overflow_width / group.size].min
			remainder = [gap * group.size, overflow_width].min - (share * group.size)

			group.each do |it|
				extra = (remainder > 0) ? 1 : 0
				shrink = [share + extra, it.width - it.min_width].min
				it.width -= shrink
				overflow_width -= shrink
				remainder -= extra
			end

			shrinkables.reject! { |it| it.width <= it.min_width }
		end
	end

	def fit_height(_renderer)
		return unless requested_height in :fit | :grow

		self.min_height = [min_height, inset_vertical + min_height_of_child_nodes].max
		natural_height = inset_vertical + height_of_child_nodes
		self.height = clamp(natural_height, min_height, max_height)
	end

	def grow_height(_renderer)
		if direction == :horizontal
			target_height = [height - inset_vertical, 0].max

			each_flow_children do |child|
				next unless child.requested_height == :grow

				child.height = clamp(target_height, child.min_height, child.max_height)
			end
		end

		remaining_height = available_internal_height
		growables = []
		each_flow_children do |child|
			growables << child if child.requested_height == :grow
		end

		while remaining_height > 0 && growables.any?
			growables.sort_by!(&:height)

			current_height = growables.first.height
			group = growables.take_while { |it| it.height == current_height }
			target_height = growables[group.size]&.height || Float::INFINITY

			gap = target_height - current_height
			share = [gap, remaining_height / group.size].min
			remainder = [gap * group.size, remaining_height].min - (share * group.size)

			group.each do |it|
				extra = (remainder > 0) ? 1 : 0
				growth = [share + extra, it.max_height - it.height].min
				it.height += growth
				remaining_height -= growth
				remainder -= extra
			end

			growables.reject! { |it| it.height >= it.max_height }
		end

		overflow_height = -available_internal_height
		shrinkables = []
		each_flow_children do |child|
			shrinkables << child if child.requested_height in :fit | :grow
		end

		while overflow_height > 0 && shrinkables.any?
			shrinkables.sort_by! { |it| -it.height }

			current_height = shrinkables.first.height
			group = shrinkables.take_while { |it| it.height == current_height }
			target_height = shrinkables[group.size]&.height || 0

			gap = current_height - target_height
			share = [gap, overflow_height / group.size].min
			remainder = [gap * group.size, overflow_height].min - (share * group.size)

			group.each do |it|
				extra = (remainder > 0) ? 1 : 0
				shrink = [share + extra, it.height - it.min_height].min
				it.height -= shrink
				overflow_height -= shrink
				remainder -= extra
			end

			shrinkables.reject! { |it| it.height <= it.min_height }
		end
	end

	def position(_renderer)
		content_row = row + border_top_width + padding.top
		content_col = col + border_left_width + padding.left
		content_width = [width - inset_horizontal, 0].max
		content_height = [height - inset_vertical, 0].max
		children_width = width_of_child_nodes
		children_height = height_of_child_nodes

		top_offset = content_row
		left_offset = content_col

		case direction
		in :vertical
			top_offset += align_offset(vertical_align, content_height, children_height)
		in :horizontal
			left_offset += align_offset(align, content_width, children_width)
		end

		previous_child = nil

		each_flow_children do |child|
			seam_overlap = collapse_border_seam(previous_child, child)

			case direction
			in :vertical
				top_offset -= seam_overlap
				child.row = top_offset
				child.col = content_col + align_offset(align, content_width, child.width)
				top_offset += child.height + gap
			in :horizontal
				left_offset -= seam_overlap
				child.row = content_row + align_offset(vertical_align, content_height, child.height)
				child.col = left_offset
				left_offset += child.width + gap
			end

			previous_child = child
		end
	end

	def draw(renderer)
		renderer.canvas.paint_box(
			row:,
			col:,
			width:,
			height:,
			border:,
			bg:
		)
	end

	def available_internal_width
		width - border_horizontal - padding.horizontal - width_of_child_nodes
	end

	def available_internal_height
		height - border_vertical - padding.vertical - height_of_child_nodes
	end

	def border_top_width
		border.top_width
	end

	def border_right_width
		border.right_width
	end

	def border_bottom_width
		border.bottom_width
	end

	def border_left_width
		border.left_width
	end

	def border_horizontal
		border_left_width + border_right_width
	end

	def border_vertical
		border_top_width + border_bottom_width
	end

	def inset_horizontal
		border_horizontal + padding.horizontal
	end

	def inset_vertical
		border_vertical + padding.vertical
	end

	def width_of_child_nodes
		case direction
		in :vertical
			max_width = 0

			each_flow_children do |child|
				max_width = child.width if child.width > max_width
			end

			max_width
		in :horizontal
			total_width = 0
			count = 0

			each_flow_children do |child|
				total_width += child.width
				count += 1
			end

			gaps = [count - 1, 0].max
			total_width + (gap * gaps) - collapsed_border_seams
		end
	end

	def height_of_child_nodes
		case direction
		in :vertical
			total_height = 0
			count = 0

			each_flow_children do |child|
				total_height += child.height
				count += 1
			end

			gaps = [count - 1, 0].max
			total_height + (gap * gaps) - collapsed_border_seams
		in :horizontal
			max_height = 0

			each_flow_children do |child|
				max_height = child.height if child.height > max_height
			end

			max_height
		end
	end

	def min_width_of_child_nodes
		case direction
		in :vertical
			max_width = 0

			each_flow_children do |child|
				max_width = child.min_width if child.min_width > max_width
			end

			max_width
		in :horizontal
			total_width = 0
			count = 0

			each_flow_children do |child|
				total_width += child.min_width
				count += 1
			end

			gaps = [count - 1, 0].max
			total_width + (gap * gaps) - collapsed_border_seams
		end
	end

	def min_height_of_child_nodes
		case direction
		in :vertical
			total_height = 0
			count = 0

			each_flow_children do |child|
				total_height += child.min_height
				count += 1
			end

			gaps = [count - 1, 0].max
			total_height + (gap * gaps) - collapsed_border_seams
		in :horizontal
			max_height = 0

			each_flow_children do |child|
				max_height = child.min_height if child.min_height > max_height
			end

			max_height
		end
	end

	def each_flow_children
		return enum_for(__method__) unless block_given?

		children.each do |child|
			next if child.popover?

			yield child
		end
	end

	private def collapsed_border_seams
		return 0 unless border_mode == :collapse

		previous_child = nil
		seams = 0

		each_flow_children do |child|
			if previous_child
				seams += collapse_border_seam(previous_child, child)
			end

			previous_child = child
		end

		seams
	end

	private def collapse_border_seam(first_child, second_child)
		return 0 unless border_mode == :collapse
		return 0 unless first_child && second_child

		case direction
		in :horizontal
			(first_child.collapse_right_edge > 0 && second_child.collapse_left_edge > 0) ? 1 : 0
		in :vertical
			(first_child.collapse_bottom_edge > 0 && second_child.collapse_top_edge > 0) ? 1 : 0
		else
			0
		end
	end

	private def validate_border_mode(value)
		unless BORDER_MODES.include?(value)
			raise ArgumentError, "Unknown border mode: #{value.inspect}"
		end

		value
	end

	private def align_offset(align, available, content)
		available_space = [available - content, 0].max

		case align
		when :left, :top
			0
		when :center, :middle
			available_space / 2
		when :right, :bottom
			available_space
		else
			0
		end
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end
end
