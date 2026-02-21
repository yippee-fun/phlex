# frozen_string_literal: true

class Phlex::TUI::CanvasNode < Phlex::TUI::Node
	def initialize(
		width: :fit,
		height: :fit,
		min_width: nil,
		min_height: nil,
		max_width: nil,
		max_height: nil,
		measure: nil,
		pointer_events: :auto,
		focusable: false,
		name: nil,
		owner: nil,
		parent: nil,
		&block
	)
		raise ArgumentError, "canvas requires a block" unless block

		@parent = parent
		@block = block
		@measure = measure
		@pointer_events = pointer_events
		@focusable = focusable
		@name = name
		@owner = owner
		@requested_width = normalize_requested_dimension(width, :width)
		@requested_height = normalize_requested_dimension(height, :height)

		if (@requested_width == :fit || @requested_height == :fit) && @measure.nil?
			raise ArgumentError, "canvas with :fit dimensions requires a measure: callable"
		end

		initial_width = (Integer === @requested_width) ? @requested_width : (min_width || 0)
		initial_height = (Integer === @requested_height) ? @requested_height : (min_height || 0)

		initialize_geometry(
			width: initial_width,
			height: initial_height,
			min_width: min_width || ((Integer === @requested_width) ? @requested_width : 0),
			min_height: min_height || ((Integer === @requested_height) ? @requested_height : 0),
			max_width: max_width || ((Integer === @requested_width) ? @requested_width : Float::INFINITY),
			max_height: max_height || ((Integer === @requested_height) ? @requested_height : Float::INFINITY)
		)
	end

	attr_reader :requested_width
	attr_reader :requested_height
	attr_reader :pointer_events
	attr_reader :focusable
	attr_reader :name
	attr_reader :owner
	attr_reader :parent

	def focus
		return false unless focusable
		return false unless owner
		return false if name.nil?

		owner.app&.focus_element(owner:, name:) || false
	end

	def focused?
		return false unless focusable
		return false unless owner
		return false if name.nil?

		owner.app&.focused_element?(owner:, name:) || false
	end

	def fit_width(renderer)
		return unless requested_width == :fit

		height_hint = (Integer === requested_height) ? clamp(requested_height, min_height, max_height) : nil
		natural_width, = measured_size(width: nil, height: height_hint)
		self.width = clamp(natural_width, min_width, max_width)
	end

	def fit_height(_renderer)
		return unless requested_height == :fit

		width_hint = if Integer === requested_width
			clamp(requested_width, min_width, max_width)
		elsif Integer === width
			width
		end

		_, natural_height = measured_size(width: width_hint, height: nil)
		self.height = clamp(natural_height, min_height, max_height)
	end

	def draw(renderer)
		render_width = [width, 0].max
		render_height = [height, 0].max
		return if render_width.zero? || render_height.zero?

		surface = Phlex::TUI::CanvasSurface.new(
			canvas: renderer.canvas,
			origin_row: row,
			origin_col: col,
			width: render_width,
			height: render_height
		)

		invoke_draw(surface)
	end

	private def measured_size(width:, height:)
		measurement = invoke_measure(width, height)
		unless Array === measurement && measurement.length == 2
			raise ArgumentError, "measure must return [width, height]"
		end

		measured_width = measurement[0]
		measured_height = measurement[1]

		unless Integer === measured_width && measured_width >= 0
			raise ArgumentError, "measure width must be an Integer >= 0"
		end

		unless Integer === measured_height && measured_height >= 0
			raise ArgumentError, "measure height must be an Integer >= 0"
		end

		[measured_width, measured_height]
	end

	private def invoke_measure(width, height)
		@measure.call(width, height)
	end

	private def invoke_draw(surface)
		@block.call(surface)
	end

	private def normalize_requested_dimension(value, name)
		return value if Integer === value && value >= 0
		return value if value == :fit || value == :grow

		raise ArgumentError, "#{name} must be an Integer >= 0, :fit, or :grow"
	end

	private def clamp(value, min, max)
		return max if min > max

		value.clamp(min, max)
	end
end
