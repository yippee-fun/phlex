# frozen_string_literal: true

class Phlex::Tux::Scroller < Phlex::TUI
	KEY_UP = ["\e[A", "\eOA", "k"].freeze
	KEY_DOWN = ["\e[B", "\eOB", "j"].freeze
	KEY_PAGE_UP = "\e[5~"
	KEY_PAGE_DOWN = "\e[6~"
	KEY_HOME = ["\e[H", "\e[1~", "\e[7~"].freeze
	KEY_END = ["\e[F", "\e[4~", "\e[8~"].freeze

	def initialize(step: 1, page_step: nil, auto_focus: true, name: :scroller, thumb: nil, track: nil, **attributes)
		@scroll_position = 0
		@step = [step, 1].max
		@page_step = page_step
		@auto_focus = auto_focus
		@auto_focused = false
		@name = name
		@thumb_renderer = thumb
		@track_renderer = track
		@attributes = attributes
		@viewport_height = 0
		@content_height = 0
		@max_scroll = 0
		@metrics_ready = false
		@pending_wheel_delta = 0
		@dragging_thumb = false
		@drag_offset = 0
		@container_node = nil
		@viewport_node = nil
		@content_node = nil
		@scrollbar_node = nil
	end

	attr_reader :scroll_position
	attr_reader :viewport_height
	attr_reader :content_height
	attr_reader :max_scroll

	def view_template(&content)
		update_metrics_from_previous_frame!
		apply_pending_wheel_scroll!

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
						yield_content { yield } if block_given?
					end
				end

				render_scrollbar
			end
		end

		auto_focus_if_needed!
	end

	def scroll_down(amount = @step)
		scroll_to(@scroll_position + amount)
	end

	def scroll_up(amount = @step)
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
		handled = case event[:key]
		when *KEY_UP
			scroll_up
			true
		when *KEY_DOWN
			scroll_down
			true
		when KEY_PAGE_UP
			scroll_up(page_amount)
			true
		when KEY_PAGE_DOWN
			scroll_down(page_amount)
			true
		when *KEY_HOME
			scroll_to(0)
			true
		when *KEY_END
			scroll_to(@max_scroll)
			true
		else
			false
		end

		event.prevent_default! if handled
	end

	private def handle_mouse_wheel(event)
		delta = event[:delta_y]
		return unless Integer === delta && delta != 0

		if @metrics_ready
			scroll_by(delta * @step)
		else
			@pending_wheel_delta += delta
			request_render!
		end

		event.prevent_default!
	end

	private def scroll_by(amount)
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
		return @page_step if @page_step
		return @viewport_height - 1 if @viewport_height > 1

		1
	end

	private def render_scrollbar
		@scrollbar_node = box(
			width: 1,
			height: :grow,
			padding: 0,
			name: scrollbar_name,
			on_mouse_down: :handle_scrollbar_mouse_down
		) do
			track_height = [@viewport_height, 0].max

			if track_height <= 0 || @content_height <= @viewport_height
				paragraph(" ")
				next
			end

			thumb_height = [(track_height.to_f * track_height / @content_height).round, 1].max
			thumb_height = [thumb_height, track_height].min
			travel = [track_height - thumb_height, 0].max
			thumb_top = if @max_scroll.zero?
				0
			else
				((@scroll_position.to_f / @max_scroll) * travel).round
			end

			track_height.times do |index|
				thumb = index >= thumb_top && index < (thumb_top + thumb_height)
				cell = scrollbar_cell(
					thumb:,
					index:,
					thumb_top:,
					thumb_height:,
					track_height:
				)
				paragraph(cell[:text], **cell[:style])
			end
		end
	end

	private def handle_scrollbar_mouse_down(event)
		return unless @metrics_ready
		node = @scrollbar_node
		return unless node

		geometry = scrollbar_geometry
		return unless geometry

		row = event[:row]
		return unless Integer === row

		relative_row = row - node.row
		return unless relative_row >= 0 && relative_row < geometry[:track_height]

		if relative_row >= geometry[:thumb_top] && relative_row < (geometry[:thumb_top] + geometry[:thumb_height])
			@dragging_thumb = true
			@drag_offset = relative_row - geometry[:thumb_top]
		elsif relative_row < geometry[:thumb_top]
			scroll_up(page_amount)
		elsif relative_row >= (geometry[:thumb_top] + geometry[:thumb_height])
			scroll_down(page_amount)
		end

		event.prevent_default!
	end

	private def handle_drag_mouse_move(event)
		return unless @dragging_thumb
		return unless @metrics_ready

		node = @scrollbar_node
		return unless node

		geometry = scrollbar_geometry
		return unless geometry

		row = event[:row]
		return unless Integer === row

		relative_row = row - node.row
		thumb_top = relative_row - @drag_offset
		thumb_top = [[thumb_top, 0].max, geometry[:travel]].min

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

	private def scrollbar_name
		[@name, :scrollbar]
	end

	private def scrollbar_cell(thumb:, index:, thumb_top:, thumb_height:, track_height:)
		renderer = thumb ? @thumb_renderer : @track_renderer
		default_text = thumb ? "█" : "│"
		default_style = { color: :bright_black }

		return { text: default_text, style: default_style } unless renderer

		result = renderer.call(
			index:,
			thumb:,
			thumb_top:,
			thumb_height:,
			track_height:,
			scroll_position: @scroll_position,
			viewport_height: @viewport_height,
			content_height: @content_height,
			max_scroll: @max_scroll,
		)

		case result
		in nil
			{ text: default_text, style: default_style }
		in String => text
			{ text:, style: default_style }
		in [String => text, Hash => style]
			{ text:, style: default_style.merge(style) }
		in Hash
			text = result[:text] || default_text
			style = result.dup
			style.delete(:text)
			{ text:, style: default_style.merge(style) }
		else
			{ text: default_text, style: default_style }
		end
	end

	private def scrollbar_geometry
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

	private def auto_focus_if_needed!
		return unless @auto_focus
		return if @auto_focused
		return unless runtime
		return unless runtime.focused_id.nil?

		element_id = [object_id, @name]
		changed = runtime.focus!(element_id)
		@auto_focused = runtime.focused?(element_id)
		request_render! if changed
	end

	private def update_metrics_from_previous_frame!
		container_node = @container_node
		viewport_node = @viewport_node
		content_node = @content_node
		return unless container_node && viewport_node && content_node

		@viewport_height = [container_node.viewport_height, 0].max
		@content_height = [content_node.natural_content_height, 0].max
		@max_scroll = [@content_height - @viewport_height, 0].max
		@metrics_ready = true
		clamp_scroll!
	end

	private def apply_pending_wheel_scroll!
		delta = @pending_wheel_delta
		return if delta.zero?
		return unless @metrics_ready

		@pending_wheel_delta = 0
		scroll_by(delta * @step)
	end
end
