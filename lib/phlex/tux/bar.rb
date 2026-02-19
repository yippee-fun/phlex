# frozen_string_literal: true

class Phlex::Tux::Bar < Phlex::TUI
	FILLS = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
	EMPTY = " "

	def initialize(progress:, color: nil, bg: nil)
		@progress = progress
		@color = color
		@bg = bg
	end

	attr_reader :progress

	def increment(amount = 1)
		self.progress += amount
	end

	def decrement(amount = 1)
		self.progress -= amount
	end

	def progress=(value)
		@progress = value
		request_render!
	end

	def view_template
		box(width: :grow, color: @color, bg: @bg) do
			embed(width: :grow, height: 1) do |width|
				next "" unless Integer === width && width > 0

				bar_text(width)
			end
		end
	end

	private def normalized_progress
		case @progress
		in Numeric
			@progress.clamp(0, 100)
		else
			raise ArgumentError, "progress must be numeric"
		end
	end

	private def bar_text(width)
		total_eighths = width * 8
		filled_eighths = ((normalized_progress * total_eighths) / 100.0).round.clamp(0, total_eighths)

		full_cells = filled_eighths / 8
		partial_eighths = filled_eighths % 8

		text = +("█" * full_cells)
		text << FILLS[partial_eighths - 1] if partial_eighths > 0

		remaining = width - text.length
		text << (EMPTY * remaining) if remaining > 0
		text
	end
end
