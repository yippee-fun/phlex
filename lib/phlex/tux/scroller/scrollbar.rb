# frozen_string_literal: true

class Phlex::Tux::Scroller::Scrollbar < Phlex::TUI
	def initialize
		@viewport_height = 0
		@content_height = 0
		@scroll_position = 0
		@max_scroll = 0
		@on_thumb_drag_start = nil
		@on_page_up = nil
		@on_page_down = nil
		@node = nil
	end

	attr_reader :node

	def update(viewport_height:, content_height:, scroll_position:, max_scroll:, on_thumb_drag_start:, on_page_up:, on_page_down:)
		@viewport_height = viewport_height
		@content_height = content_height
		@scroll_position = scroll_position
		@max_scroll = max_scroll
		@on_thumb_drag_start = on_thumb_drag_start
		@on_page_up = on_page_up
		@on_page_down = on_page_down
		nil
	end

	def geometry
		track_height = [@viewport_height, 0].max
		return nil if track_height <= 0 || @content_height <= @viewport_height

		thumb_height = [(track_height.to_f * track_height / @content_height).round, 1].max
		thumb_height = [thumb_height, track_height].min
		travel = [track_height - thumb_height, 0].max
		thumb_top = if @max_scroll.zero? || travel.zero?
			0
		else
			((@scroll_position.to_f / @max_scroll) * travel).round
		end

		{
			track_height:,
			thumb_height:,
			travel:,
			thumb_top:,
		}
	end

	def view_template
		@node = box(
			width: 1,
			height: :grow,
			padding: 0,
			name: :scrollbar,
			on_mouse_down: :handle_mouse_down
		) do
			geometry = self.geometry

			unless geometry
				paragraph(" ")
				next
			end

			track_height = geometry[:track_height]
			thumb_top = geometry[:thumb_top]
			thumb_height = geometry[:thumb_height]

			track_height.times do |index|
				thumb = index >= thumb_top && index < (thumb_top + thumb_height)
				paragraph(thumb ? "█" : "│", color: :bright_black)
			end
		end
	end

	private def handle_mouse_down(event)
		node = @node
		return unless node

		geometry = self.geometry
		return unless geometry

		row = event.row
		return unless Integer === row

		relative_row = row - node.row
		return unless relative_row >= 0 && relative_row < geometry[:track_height]

		if relative_row >= geometry[:thumb_top] && relative_row < (geometry[:thumb_top] + geometry[:thumb_height])
			offset = relative_row - geometry[:thumb_top]
			@on_thumb_drag_start&.call(offset)
		elsif relative_row < geometry[:thumb_top]
			@on_page_up&.call
		elsif relative_row >= (geometry[:thumb_top] + geometry[:thumb_height])
			@on_page_down&.call
		end

		event.prevent_default!
	end
end
