#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "phlex"

class DragDropBoard < Phlex::TUI
	def initialize
		@left_items = ["Ruby", "Crystal", "Elixir"]
		@right_items = []
		@dragging = nil
		@hover_zone = nil
	end

	def start_drag(event, label, from:)
		entry = runtime&.event_for(event[:current_target])
		node = entry && entry[:node]

		offset_col = if node && Integer === node.col
			event[:col] - node.col
		else
			0
		end

		offset_row = if node && Integer === node.row
			event[:row] - node.row
		else
			0
		end

		@dragging = {
			label:,
			from:,
			offset_col:,
			offset_row:,
			col: event[:col] - offset_col,
			row: event[:row] - offset_row,
		}
	end

	def track_drag(event)
		return unless @dragging

		@dragging[:col] = event[:col] - @dragging[:offset_col]
		@dragging[:row] = event[:row] - @dragging[:offset_row]
	end

	def drop_in(zone)
		return unless @dragging

		label = @dragging[:label]
		from = @dragging[:from]

		if from != zone
			source = items_for(from)
			target = items_for(zone)
			if source.delete(label)
				target << label
			end
		end

		@dragging = nil
	end

	def cancel_drag(...)
		@dragging = nil
	end

	def items_for(zone)
		(zone == :left) ? @left_items : @right_items
	end

	def zone_border(zone)
		active = @hover_zone == zone || @dragging&.dig(:from) == zone
		active ? :thick : :thin
	end

	def draggable_item(label, from:)
		dragging_this = @dragging && @dragging[:label] == label && @dragging[:from] == from

		box(
			name: [from, label],
			border: dragging_this ? :thick : :thin,
			padding: [0, 1],
			on_mouse_down: -> (event) { start_drag(event, label, from:) }
		) do
			paragraph(label)
		end
	end

	def drop_zone(title, name:, zone:, items:)
		box(
			name:,
			width: :grow,
			border: zone_border(zone),
			padding: 1,
			gap: 1,
			on_mouse_enter: -> (_event) { @hover_zone = zone },
			on_mouse_leave: -> (_event) { @hover_zone = nil if @hover_zone == zone },
			on_mouse_up: -> (_event) { drop_in(zone) }
		) do
			paragraph(title, bold: true)

			if items.empty?
				paragraph("(empty)", color: :bright_black)
			else
				items.each do |label|
					draggable_item(label, from: zone)
				end
			end
		end
	end

	def view_template
		box(
			name: :board,
			border: :rounded,
			padding: 1,
			gap: 1,
			on_mouse_up: :cancel_drag,
			on_mouse_move: (@dragging ? :track_drag : nil)
		) do
			paragraph("Drag and Drop", bold: true)
			paragraph("Hold mouse down on an item, then release over a lane", color: :bright_cyan)

			hstack(gap: 1) do
				drop_zone("Backlog", name: :left_zone, zone: :left, items: @left_items)
				drop_zone("In Progress", name: :right_zone, zone: :right, items: @right_items)
			end

			status = @dragging ? "Dragging: #{@dragging[:label]}" : "Dragging: none"
			paragraph(status, color: :bright_black)
			paragraph("Ctrl+C exits", color: :bright_black)
		end

		if @dragging
			popover(anchor: :canvas, left: @dragging[:col], top: @dragging[:row], z: 20, pointer_events: :none) do
				box(border: :thick, padding: [0, 1]) do
					paragraph(@dragging[:label], color: :bright_cyan)
				end
			end
		end
	end
end

class DemoTUIApp < Phlex::TUI::App
	def initialize(...)
		super
		@drag_drop_board = DragDropBoard.new
		@frame_times = []
		@render_samples = []
		@draw_samples = []
	end

	def update(dt)
		now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
		@frame_times << now

		cutoff = now - 1.0
		@frame_times.shift while !@frame_times.empty? && @frame_times[0] < cutoff

		record_sample(@render_samples, last_render_duration)
		record_sample(@draw_samples, last_draw_duration)

		nil
	end

	def render_fps
		@frame_times.length
	end

	def last_frame_ms
		duration = last_frame_duration
		return "-" unless duration

		(duration * 1000.0).round(2)
	end

	def theoretical_fps
		duration = last_frame_duration
		return "-" unless duration && duration.positive?

		(1.0 / duration).round(1)
	end

	def draw_ms
		duration = last_draw_duration
		return "-" unless duration

		(duration * 1000.0).round(2)
	end

	def draw_theoretical_fps
		duration = last_draw_duration
		return "-" unless duration && duration.positive?

		(1.0 / duration).round(1)
	end

	def render_ms
		duration = last_render_duration
		return "-" unless duration

		(duration * 1000.0).round(2)
	end

	def render_theoretical_fps
		duration = last_render_duration
		return "-" unless duration && duration.positive?

		(1.0 / duration).round(1)
	end

	def avg_render_ms
		avg_ms(@render_samples)
	end

	def avg_render_fps
		avg_fps(@render_samples)
	end

	def avg_draw_ms
		avg_ms(@draw_samples)
	end

	def avg_draw_fps
		avg_fps(@draw_samples)
	end

	def view_template
		box(width: :grow, height: :grow, border: :rounded, padding: 1, gap: 1) do
			paragraph("Phlex::TUI Demo", bold: true)
			paragraph("Mouse-driven drag and drop", color: :bright_cyan)
			paragraph("Actual FPS (last 1s): #{render_fps}", color: :bright_black)
			paragraph("Frame loop cost: #{last_frame_ms}ms | Max from loop: #{theoretical_fps} fps", color: :bright_black)
			paragraph("Render-only cost: #{render_ms}ms | Max from render: #{render_theoretical_fps} fps", color: :bright_black)
			paragraph("Avg render (30f): #{avg_render_ms}ms | Avg max from render: #{avg_render_fps} fps", color: :bright_black)
			paragraph("Draw cost only: #{draw_ms}ms | Max from draw: #{draw_theoretical_fps} fps", color: :bright_black)
			paragraph("Avg draw (30f): #{avg_draw_ms}ms | Avg max from draw: #{avg_draw_fps} fps", color: :bright_black)
			paragraph("Event-driven renderer: values update only when a frame is rendered", color: :bright_black)
			hr(border: :thin)
			render(@drag_drop_board)
		end
	end

	private def record_sample(samples, duration)
		return unless duration && duration.positive?

		samples << duration
		samples.shift while samples.length > 30
	end

	private def avg_ms(samples)
		return "-" if samples.empty?

		((samples.sum / samples.length) * 1000.0).round(2)
	end

	private def avg_fps(samples)
		return "-" if samples.empty?

		avg = samples.sum / samples.length
		return "-" unless avg.positive?

		(1.0 / avg).round(1)
	end
end

DemoTUIApp.new.start(fps: nil)
