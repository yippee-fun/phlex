# frozen_string_literal: true

class Phlex::TUI::BorderColor
	def self.parse(value)
		case value
		in nil
			new(top: nil, right: nil, bottom: nil, left: nil)
		in Hash
			new(
				top: value.fetch(:top, nil),
				right: value.fetch(:right, nil),
				bottom: value.fetch(:bottom, nil),
				left: value.fetch(:left, nil)
			)
		in Phlex::TUI::BorderColor
			value
		else
			new(top: value, right: value, bottom: value, left: value)
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
end
