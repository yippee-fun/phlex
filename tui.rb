#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "phlex"

class TimerCard < Phlex::TUI
	def initialize
		@ticks = 0
		@started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
	end

	def tick!
		@ticks += 1
	end

	def view_template
		elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second) - @started_at
		pulse = (@ticks % 2).zero? ? "*" : "."
		minus_border = focused?(:minus) ? :thick : :rounded
		plus_border = focused?(:plus) ? :thick : :rounded

		box(border: :rounded, padding: 1, gap: 1) do
			paragraph("Persistent Child Component", bold: true)
			paragraph("tick: #{@ticks} #{pulse}", color: :bright_cyan)
			paragraph("elapsed: #{format('%.1f', elapsed)}s")

			hstack(gap: 1) do
				box(focusable: true, name: :minus, border: minus_border, padding: [0, 1]) { "-" }
				box(focusable: true, name: :plus, border: plus_border, padding: [0, 1]) { "+" }
			end
		end
	end
end

class DemoTUIApp < Phlex::TUI::App
	def initialize(...)
		super
		@renders = 0
		@last_dt = 0.0
		@pulse_thread = nil
		@timer_card = TimerCard.new
	end

	def start(...)
		start_pulse_thread
		super
	ensure
		stop_pulse_thread
	end

	def update(dt)
		@last_dt = dt
		@renders += 1
	end

	def view_template
		box(width: :grow, height: :grow, border: :rounded, padding: 1, gap: 1) do
			paragraph("Phlex::TUI Demo", bold: true)
			paragraph("Queue loop + request_render!", color: :bright_cyan)
			paragraph("Arrow keys move focus, Ctrl+C exits", color: :bright_black)
			hr(border: :thin)
			render(@timer_card)
			hr(border: :thin)

			paragraph("renders: #{@renders}")
			paragraph("dt: #{format('%.3f', @last_dt)}s")
			paragraph("size: #{cols}x#{rows}")
		end
	end

	private def start_pulse_thread
		return if @pulse_thread

		@pulse_thread = Thread.new do
			loop do
				sleep(1)
				@timer_card.tick!
				request_render!
			end
		end
	end

	private def stop_pulse_thread
		thread = @pulse_thread
		@pulse_thread = nil
		return unless thread

		thread.kill
		thread.join(0.1)
	end
end

DemoTUIApp.new.start
