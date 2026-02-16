# frozen_string_literal: true

class Phlex::TUI::Col < Phlex::TUI::Box
	def initialize(*, colspan: 1, direction: :vertical, border_mode: :separate, **)
		raise ArgumentError, "colspan must be an Integer >= 1" unless Integer === colspan && colspan >= 1

		@colspan = colspan
		super(*, direction:, border_mode:, **)
	end

	attr_reader :colspan
end
