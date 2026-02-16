# frozen_string_literal: true

require "io/console"

class Phlex::TUI::App < Phlex::TUI
	CURSOR_HIDE = "\e[?25l"
	CURSOR_SHOW = "\e[?25h"
	ENTER_ALT_SCREEN = "\e[?1049h"
	EXIT_ALT_SCREEN = "\e[?1049l"
	RESET_STYLE = "\e[0m"

	def initialize(stdout: $stdout)
		@stdout = stdout
		@running = false
		@differ = Phlex::TUI::FrameDiffer.new
		@last_frame_time = nil
		@session_active = false
		@rows = 24
		@cols = 80
	end

	attr_reader :rows
	attr_reader :cols

	def start(fps: nil)
		if fps
			raise ArgumentError, "fps must be greater than zero" unless fps.positive?
		end
		raise "Phlex::TUI::App requires a TTY output stream." unless @stdout.tty?

		@running = true
		@last_frame_time = nil
		previous_lines = []
		last_size = nil
		frame_duration = fps ? (1.0 / fps) : nil

		enter_terminal_session

		while @running
			frame_started_at = monotonic_time
			rows, cols = terminal_size
			@rows = rows
			@cols = cols
			size = [rows, cols]
			resized = size != last_size
			last_size = size

			dt = frame_delta(frame_started_at)
			update(dt)

			current_lines = render_lines(width: cols, height: rows)
			output = if resized || previous_lines.empty?
				@differ.full(current_lines, clear: true)
			else
				@differ.diff(previous_lines, current_lines)
			end

			unless output.empty?
				@stdout.write(output)
				@stdout.flush
			end

			previous_lines = current_lines
			sleep_remaining(frame_started_at, frame_duration)
		end
	rescue Interrupt
		@running = false
	ensure
		exit_terminal_session
	end

	def stop
		@running = false
	end

	def update(_dt)
	end

	private def render_lines(width:, height:)
		tree = call(Phlex::TUI::Tree.new)
		renderer = Phlex::TUI::Render.new(tree, width:, height:)
		renderer.render_canvas.styled_lines
	end

	private def terminal_size
		console = @stdout.respond_to?(:winsize) ? @stdout : IO.console
		rows, cols = console&.winsize

		rows = 24 unless Integer === rows && rows.positive?
		cols = 80 unless Integer === cols && cols.positive?

		[rows, cols]
	end

	private def enter_terminal_session
		@session_active = true
		@stdout.write(ENTER_ALT_SCREEN)
		@stdout.write(CURSOR_HIDE)
		@stdout.write("\e[H\e[2J")
		@stdout.flush
	end

	private def exit_terminal_session
		return unless @session_active

		@stdout.write(RESET_STYLE)
		@stdout.write(CURSOR_SHOW)
		@stdout.write(EXIT_ALT_SCREEN)
		@stdout.flush
		@session_active = false
	end

	private def monotonic_time
		Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
	end

	private def frame_delta(now)
		last = @last_frame_time
		@last_frame_time = now
		return 0.0 unless last

		now - last
	end

	private def sleep_remaining(frame_started_at, frame_duration)
		return unless frame_duration

		remaining = frame_duration - (monotonic_time - frame_started_at)
		sleep(remaining) if remaining.positive?
	end
end
