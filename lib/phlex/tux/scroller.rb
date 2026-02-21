# frozen_string_literal: true

class Phlex::Tux::Scroller < Phlex::TUI
	LINE_STEP = 1

	def initialize(**attributes)
		@scroll_position = 0
		@attributes = attributes
		@name = :scroller
		@viewport_height = 0
		@content_height = 0
		@max_scroll = 0
		@metrics_ready = false
		@overflowing = false
		@pending_wheel_delta = 0
		@dragging_thumb = false
		@drag_offset = 0
		@container_node = nil
		@viewport_node = nil
		@content_node = nil
		@scrollbar = Scrollbar.new
	end

	attr_reader :scroll_position
	attr_reader :viewport_height
	attr_reader :content_height
	attr_reader :max_scroll

	def view_template(&content)
		first_frame = @container_node.nil?
		update_metrics_from_previous_frame!
		apply_pending_wheel_scroll!
		update_scrollbar!

		container_attributes = @attributes.merge(
			focusable: true,
			name: @name,
			on_key_down: :handle_key_down,
			on_mouse_wheel: :handle_mouse_wheel,
			on_mouse_move: :handle_drag_mouse_move,
			on_mouse_up: :handle_drag_mouse_up
		)

		@container_node = box(**container_attributes) do
			hstack(width: :grow, height: :grow) do
				@viewport_node = box(width: :grow, height: :grow, overflow: :none, padding: 0) do
					@content_node = box(width: :grow, padding: { top: -@scroll_position }) do
						yield_content { content.call } if content
					end
				end

				render(@scrollbar) if scroll_enabled?
			end
		end

		request_render! if first_frame
	end

	def scroll_down(amount = LINE_STEP)
		scroll_to(@scroll_position + amount)
	end

	def scroll_up(amount = LINE_STEP)
		scroll_to(@scroll_position - amount)
	end

	def scroll_to(position)
		previous = @scroll_position
		@scroll_position = [Integer(position), 0].max
		clamp_scroll! if @metrics_ready
		changed = @scroll_position != previous
		request_render! if changed
		changed
	end

	private def handle_key_down(event)
		return unless scroll_enabled?

		handled = if event.key?(:up, :k)
			scroll_up
			true
		elsif event.key?(:down, :j)
			scroll_down
			true
		elsif event.key?(:page_up)
			scroll_up(page_amount)
			true
		elsif event.key?(:page_down)
			scroll_down(page_amount)
			true
		elsif event.key?(:home)
			scroll_to(0)
			true
		elsif event.key?(:end)
			scroll_to(@max_scroll)
			true
		else
			false
		end

		event.prevent_default! if handled
	end

	private def handle_mouse_wheel(event)
		return unless scroll_enabled?

		delta = event.delta_y
		return unless Integer === delta && delta != 0

		if @metrics_ready
			scroll_by(delta * LINE_STEP)
		else
			@pending_wheel_delta += delta
			request_render!
		end

		event.prevent_default!
	end

	private def scroll_by(amount)
		return unless scroll_enabled?
		return if amount.zero?

		previous = @scroll_position
		@scroll_position += amount
		clamp_scroll! if @metrics_ready
		request_render! if @scroll_position != previous
	end

	private def clamp_scroll!
		if @scroll_position < 0
			@scroll_position = 0
		elsif @scroll_position > @max_scroll
			@scroll_position = @max_scroll
		end
	end

	private def page_amount
		return @viewport_height - 1 if @viewport_height > 1

		1
	end

	private def update_scrollbar!
		@scrollbar.update(
			viewport_height: @viewport_height,
			content_height: @content_height,
			scroll_position: @scroll_position,
			max_scroll: @max_scroll,
			on_thumb_drag_start: -> (offset) { start_thumb_drag(offset) },
			on_page_up: -> { scroll_up(page_amount) },
			on_page_down: -> { scroll_down(page_amount) }
		)
	end

	private def start_thumb_drag(offset)
		return unless Integer === offset

		@dragging_thumb = true
		@drag_offset = offset
	end

	private def handle_drag_mouse_move(event)
		return unless @dragging_thumb
		return unless @metrics_ready

		node = @scrollbar.node
		return unless node

		geometry = @scrollbar.geometry
		return unless geometry

		row = event.row
		return unless Integer === row

		relative_row = row - node.row
		thumb_top = relative_row - @drag_offset
		thumb_top = thumb_top.clamp(0, geometry[:travel])

		target_scroll = if geometry[:travel].zero? || @max_scroll.zero?
			0
		else
			((thumb_top.to_f / geometry[:travel]) * @max_scroll).round
		end

		scroll_to(target_scroll)
		event.prevent_default!
	end

	private def handle_drag_mouse_up(event)
		return unless @dragging_thumb

		@dragging_thumb = false
		@drag_offset = 0
		event.prevent_default!
	end

	private def update_metrics_from_previous_frame!
		viewport_node = @viewport_node
		content_node = @content_node
		return unless viewport_node && content_node

		@viewport_height = [viewport_node.viewport_height, 0].max
		@content_height = [content_node.natural_content_height, 0].max
		@max_scroll = [@content_height - @viewport_height, 0].max
		@metrics_ready = true
		previous_overflowing = @overflowing
		@overflowing = @content_height > @viewport_height

		if !@overflowing && !@scroll_position.zero?
			@scroll_position = 0
		end

		clamp_scroll!

		if previous_overflowing != @overflowing
			request_render!
		end
	end

	private def apply_pending_wheel_scroll!
		delta = @pending_wheel_delta
		return if delta.zero?
		return unless scroll_enabled?

		@pending_wheel_delta = 0
		scroll_by(delta * LINE_STEP)
	end

	private def scroll_enabled?
		@metrics_ready && @overflowing
	end
end
