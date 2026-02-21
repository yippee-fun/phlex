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
		parent: nil,
		&block
	)
		raise ArgumentError, "canvas requires a block" unless block

		@parent = parent
		@block = block
		@measure = measure
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

		invoke_draw(surface, render_width, render_height)
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
		callable = @measure
		arity = positional_arity(callable)

		case arity
		in :rest
			callable.call(width, height)
		in 0
			callable.call
		in 1
			callable.call(width)
		else
			callable.call(width, height)
		end
	end

	private def invoke_draw(surface, width, height)
		arity = positional_arity(@block)

		case arity
		in :rest
			@block.call(surface, width, height)
		in 0
			@block.call
		in 1
			@block.call(surface)
		in 2
			@block.call(surface, width)
		else
			@block.call(surface, width, height)
		end
	end

	private def positional_arity(callable)
		parameters = callable.parameters
		has_rest = false
		count = 0

		i = 0
		while i < parameters.length
			type, = parameters[i]
			if type == :rest
				has_rest = true
			elsif type == :req || type == :opt
				count += 1
			end
			i += 1
		end

		return :rest if has_rest

		count
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
