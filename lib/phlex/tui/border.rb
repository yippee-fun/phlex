# frozen_string_literal: true

class Phlex::TUI::Border
	STYLES = [:thin, :thick, :double, :rounded, :transparent].freeze

	def self.parse(value)
		case value
		in nil
			new(top: nil, right: nil, bottom: nil, left: nil)
		in Symbol
			new(top: value, right: value, bottom: value, left: value)
		in Hash
			new(
				top: value.fetch(:top, nil),
				right: value.fetch(:right, nil),
				bottom: value.fetch(:bottom, nil),
				left: value.fetch(:left, nil),
			)
		in Phlex::TUI::Border
			value
		else
			raise ArgumentError, "Border must be nil, a Symbol, Hash, or Border, got: #{value.class}"
		end
	end

	def initialize(top:, right:, bottom:, left:)
		@top = validate(top)
		@right = validate(right)
		@bottom = validate(bottom)
		@left = validate(left)

		freeze
	end

	attr_reader :top, :right, :bottom, :left

	def top_width
		@top.nil? ? 0 : 1
	end

	def right_width
		@right.nil? ? 0 : 1
	end

	def bottom_width
		@bottom.nil? ? 0 : 1
	end

	def left_width
		@left.nil? ? 0 : 1
	end

	def horizontal
		left_width + right_width
	end

	def vertical
		top_width + bottom_width
	end

	def none?
		@top.nil? && @right.nil? && @bottom.nil? && @left.nil?
	end

	private def validate(style)
		return nil if style.nil?

		unless STYLES.include?(style)
			raise ArgumentError, "Unknown border style: #{style.inspect}"
		end

		style
	end
end
