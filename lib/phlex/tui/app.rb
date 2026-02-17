# frozen_string_literal: true

require "io/console"
require "thread"

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
		@runtime = Phlex::TUI::Runtime.new
		@last_frame_time = nil
		@last_render_at = nil
		@session_active = false
		@rows = 24
		@cols = 80
		@frame_interval = nil
		@render_requested = false
		@render_signal_pending = false
		@event_queue = Queue.new
		@queue_mutex = Mutex.new
		@input_thread = nil
		@input_mode_saved = nil
		@input_mode_active = false
	end

	attr_reader :rows
	attr_reader :cols
	attr_reader :runtime

	def app
		self
	end

	def start(fps: nil)
		if fps
			raise ArgumentError, "fps must be greater than zero" unless fps.positive?
		end
		raise "Phlex::TUI::App requires a TTY output stream." unless @stdout.tty?

		@running = true
		@frame_interval = fps ? (1.0 / fps) : nil
		@last_frame_time = nil
		@last_render_at = nil
		@render_requested = false
		@render_signal_pending = false
		@event_queue = Queue.new
		previous_lines = []
		last_size = nil
		previous_winch_handler = nil

		enter_terminal_session
		previous_winch_handler = install_winch_handler
		start_input_thread
		request_render!

		while @running
			event = @event_queue.pop
			handle_event(event)
			next unless @running
			next unless render_requested?

			sleep_until_frame_due

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
			@last_render_at = frame_started_at

			@queue_mutex.synchronize do
				@render_requested = false unless @render_signal_pending
			end
		end
	rescue Interrupt
		@running = false
	ensure
		restore_winch_handler(previous_winch_handler)
		stop_input_thread
		disable_input_mode
		exit_terminal_session
	end

	def stop
		@running = false
		@event_queue << :stop
	end

	def request_render!
		@queue_mutex.synchronize do
			@render_requested = true
			next if @render_signal_pending

			@render_signal_pending = true
			@event_queue << :render
		end

		nil
	end

	def update(_dt)
	end

	private def render_lines(width:, height:)
		@runtime.begin_frame!
		tree = call(Phlex::TUI::Tree.new, context: self)
		renderer = Phlex::TUI::Render.new(tree, width:, height:)
		lines = renderer.render_canvas.styled_lines
		@runtime.finalize_frame!
		lines
	end

	private def render_requested?
		@queue_mutex.synchronize { @render_requested }
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

	private def sleep_until_frame_due
		return unless @frame_interval
		return unless @last_render_at

		remaining = @frame_interval - (monotonic_time - @last_render_at)
		sleep(remaining) if remaining.positive?
	end

	private def install_winch_handler
		Signal.trap("WINCH") { enqueue_event(:resize) }
	rescue ArgumentError, ThreadError
		nil
	end

	private def restore_winch_handler(handler)
		return unless handler

		Signal.trap("WINCH", handler)
	rescue ArgumentError, ThreadError
		nil
	end

	private def start_input_thread
		console = IO.console
		return unless console&.tty?
		return unless enable_input_mode

		@input_thread = Thread.new do
			while @running
				key = read_key(console)
				break unless @running
				next unless key

				enqueue_event([:input, key])
			end
		rescue IOError, SystemCallError
			nil
		end
	end

	private def stop_input_thread
		thread = @input_thread
		@input_thread = nil
		return unless thread

		thread.kill
		thread.join(0.1)
	end

	private def read_key(io)
		return nil unless io.wait_readable(0.05)

		key = io.read_nonblock(1, exception: false)
		return nil if key == :wait_readable || key.nil?
		return key unless key == "\e"

		buffer = +"\e"
		while io.wait_readable(0.001)
			chunk = io.read_nonblock(1, exception: false)
			break if chunk == :wait_readable || chunk.nil?

			buffer << chunk
			break if buffer.length >= 3
		end

		buffer
	end

	private def enable_input_mode
		return true if @input_mode_active

		@input_mode_saved = `stty -g`.chomp
		return false if @input_mode_saved.empty?

		@input_mode_active = system("stty", "-icanon", "-echo", "min", "1", "time", "0")
	rescue SystemCallError
		false
	end

	private def disable_input_mode
		return unless @input_mode_active
		return unless @input_mode_saved && !@input_mode_saved.empty?

		system("stty", @input_mode_saved)
	ensure
		@input_mode_saved = nil
		@input_mode_active = false
	end

	private def enqueue_event(event)
		@event_queue << event
	end

	private def handle_event(event)
		case event
		when :render
			@queue_mutex.synchronize { @render_signal_pending = false }
		when :resize
			request_render!
		when :stop
			nil
		when Array
			handle_input(event[1]) if event[0] == :input && String === event[1]
		end
	end

	private def handle_input(key)
		if key == "\u0003"
			stop
			return
		end

		focus_changed = case key
		when "\e[C", "\e[B"
			@runtime.focus_next!
		when "\e[D", "\e[A"
			@runtime.focus_previous!
		else
			false
		end

		request_render! if focus_changed
	end
end
