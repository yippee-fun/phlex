# frozen_string_literal: true

class Phlex::TUI::Render
	attr_reader :canvas
	attr_reader :width
	attr_reader :height

	def initialize(tree_or_root, width: 100, height: 20)
		if Phlex::TUI::Tree === tree_or_root
			@tree = tree_or_root
			@root = tree_or_root.root
		else
			@tree = nil
			@root = tree_or_root
		end
		@requested_width = normalize_dimension(width, :width)
		@requested_height = normalize_dimension(height, :height)
		@width = layout_dimension(@requested_width, fallback: 100)
		@height = layout_dimension(@requested_height, fallback: 20)
		@canvas = nil
		@popover_draw_queue = []
		@discovery_order = 0
	end

	def call
		render_canvas
		@canvas.to_s
	end

	def render_canvas
		seed_root_canvas
		layout_tree
		resolve_canvas_dimensions

		if fit_canvas?
			seed_root_canvas
			layout_tree
			resolve_canvas_dimensions
		end

		draw_tree
		@canvas
	end

	private def seed_root_canvas
		@root.row = 0
		@root.col = 0

		if Integer === @requested_width
			@root.width = @requested_width
			@root.min_width = @requested_width
			@root.max_width = @requested_width
		end

		if Integer === @requested_height
			@root.height = @requested_height
			@root.min_height = @requested_height
			@root.max_height = @requested_height
		end
	end

	private def resolve_canvas_dimensions
		@width = if Integer === @requested_width
			@requested_width
		else
			[@root.width, 0].max
		end

		@height = if Integer === @requested_height
			@requested_height
		else
			[@root.height, 0].max
		end

		@canvas = Phlex::TUI::Canvas.new(width:, height:)
	end

	private def layout_tree
		traverse_bottom_up(@root, :fit_width)
		traverse_top_down(@root, :grow_width)
		traverse_top_down(@root, :normalize_table_widths)
		traverse_top_down(@root, :wrap_text)
		traverse_bottom_up(@root, :fit_width)
		traverse_top_down(@root, :grow_width)
		traverse_bottom_up(@root, :fit_height)
		traverse_top_down(@root, :grow_height)
		traverse_top_down(@root, :normalize_table_heights)
		traverse_bottom_up(@root, :fit_height)
		traverse_top_down(@root, :grow_height)
		traverse_top_down(@root, :position)
	end

	private def fit_canvas?
		@requested_width == :fit || @requested_height == :fit
	end

	private def normalize_dimension(value, name)
		return value if Integer === value && value >= 0
		return :fit if value == :fit

		raise ArgumentError, "#{name} must be an Integer >= 0 or :fit"
	end

	private def layout_dimension(value, fallback:)
		(Integer === value) ? value : fallback
	end

	private def traverse_top_down(node, phase)
		node.__send__(phase, self)
		node.children.each { |child| traverse_top_down(child, phase) }
	end

	private def traverse_bottom_up(node, phase)
		node.children.each { |child| traverse_bottom_up(child, phase) }
		node.__send__(phase, self)
	end

	private def draw_tree
		@popover_draw_queue.clear
		@discovery_order = 0

		traverse_static_draw(@root, popover_ancestor: false)

		@popover_draw_queue
			.sort_by { |entry| [entry[:node].z, entry[:order]] }
			.each { |entry| draw_popover_subtree(entry[:node]) }
	end

	private def traverse_static_draw(node, popover_ancestor:)
		if node.popover?
			@popover_draw_queue << { node:, order: @discovery_order }
			@discovery_order += 1
			popover_ancestor = true
		end

		if popover_ancestor
			node.children.each do |child|
				traverse_static_draw(child, popover_ancestor:)
			end
			return
		end

		canvas.with_clip(**node_bounds(node)) do
			node.draw(self)
		end

		canvas.with_clip(**children_bounds(node)) do
			node.children.each do |child|
				traverse_static_draw(child, popover_ancestor:)
			end
		end
	end

	private def draw_popover_subtree(node)
		canvas.with_clip(**node_bounds(node)) do
			node.draw(self)
		end

		canvas.with_clip(**children_bounds(node)) do
			node.each_flow_children do |child|
				draw_popover_subtree(child)
			end
		end
	end

	private def node_bounds(node)
		{ row: node.row, col: node.col, width: node.width, height: node.height }
	end

	private def children_bounds(node)
		if Phlex::TUI::Box === node && node.overflow == :none
			{
				row: node.row + node.border_top_width,
				col: node.col + node.border_left_width,
				width: [node.width - node.border_horizontal, 0].max,
				height: [node.height - node.border_vertical, 0].max,
			}
		else
			node_bounds(node)
		end
	end
end
