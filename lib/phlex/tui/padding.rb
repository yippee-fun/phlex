# frozen_string_literal: true

class Phlex::TUI::Padding
	def self.parse(value)
		case value
		in Integer
			new(top: value, right: value, bottom: value, left: value)
		in [Integer => y, Integer => x]
			new(top: y, right: x, bottom: y, left: x)
		in [Integer => top, Integer => right, Integer => bottom, Integer => left]
			new(top:, right:, bottom:, left:)
		in Hash
			new(top: value[:top] || 0, right: value[:right] || 0, bottom: value[:bottom] || 0, left: value[:left] || 0)
		end
	end

	def initialize(top:, right:, bottom:, left:)
		@top = top
		@right = right
		@bottom = bottom
		@left = left

		freeze
	end

	attr_reader :top, :right, :bottom, :left

	def vertical
		@top + @bottom
	end

	def horizontal
		@left + @right
	end
end
