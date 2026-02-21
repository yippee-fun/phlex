# frozen_string_literal: true

require "io/console"
require "base64"

class Phlex::TUI::App < Phlex::TUI
	CURSOR_HIDE = "\e[?25l"
	CURSOR_SHOW = "\e[?25h"
	ENTER_ALT_SCREEN = "\e[?1049h"
	EXIT_ALT_SCREEN = "\e[?1049l"
	RESET_STYLE = "\e[0m"
	ENABLE_MOUSE_TRACKING = "\e[?1000h\e[?1003h\e[?1006h"
	DISABLE_MOUSE_TRACKING = "\e[?1006l\e[?1003l\e[?1000l"
	ENABLE_BRACKETED_PASTE = "\e[?2004h"
	DISABLE_BRACKETED_PASTE = "\e[?2004l"
	BRACKETED_PASTE_START = "\e[200~"
	BRACKETED_PASTE_END = "\e[201~"

	KEY_NAMES = {
	"\e[A" => :up,
	"\eOA" => :up,
	"\e[B" => :down,
	"\eOB" => :down,
	"\e[C" => :right,
	"\eOC" => :right,
	"\e[D" => :left,
	"\eOD" => :left,
	"\eb" => :alt_left,
	"\ef" => :alt_right,
	"\e[1;2A" => :shift_up,
	"\e[1;2B" => :shift_down,
	"\e[1;2C" => :shift_right,
	"\e[1;2D" => :shift_left,
	"\e[1;3D" => :alt_left,
	"\e[1;3C" => :alt_right,
	"\e[1;4D" => :shift_alt_left,
	"\e[1;4C" => :shift_alt_right,
	"\e[1;9D" => :cmd_left,
	"\e[1;9C" => :cmd_right,
	"\e[1;10D" => :shift_cmd_left,
	"\e[1;10C" => :shift_cmd_right,
	"\e\b" => :alt_backspace,
	"\e\u007f" => :alt_backspace,
	"\ec" => :alt_c,
	"\eC" => :alt_c,
	"\e[5~" => :page_up,
	"\e[6~" => :page_down,
	"\e[H" => :home,
	"\e[1~" => :home,
	"\e[7~" => :home,
	"\e[F" => :end,
	"\e[4~" => :end,
	"\e[8~" => :end,
	"\r" => :enter,
	"\n" => :enter,
	"\t" => :tab,
	"\u0016" => :ctrl_v,
	"\u0018" => :ctrl_x,
	"\u0011" => :ctrl_q,
	"\u0007" => :ctrl_g,
	"\u0015" => :cmd_backspace,
	"\177" => :backspace,
	"\e[3~" => :delete,
	}.freeze

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
		@render_request_version = 0
		@rendered_version = 0
		@render_signal_pending = false
		@event_queue = Queue.new
		@queue_mutex = Mutex.new
		@pending_mouse_move_raw = nil
		@mouse_move_signal_pending = false
		@input_thread = nil
		@input_io = nil
		@input_mode_saved = nil
		@input_mode_active = false
		@hovered_path = []
		@last_pointer_col = nil
		@last_pointer_row = nil
		@mouse_capture_ref = nil
		@last_frame_duration = nil
		@last_render_duration = nil
		@last_draw_duration = nil
		@paste_mode = false
		@paste_buffer = +""
		@clipboard = +""
		@input_buffer = +""
	end

	attr_reader :rows
	attr_reader :cols
	attr_reader :runtime
	attr_reader :last_frame_duration
	attr_reader :last_render_duration
	attr_reader :last_draw_duration

	def focus_element(owner:, name:)
		element_id = @runtime.element_ref(owner:, name:)
		previous_focused_id = @runtime.focused_id
		changed = @runtime.focus!(element_id)
		return false unless changed

		dispatch_focus_transition(previous_focused_id, @runtime.focused_id)
		request_render!
		true
	end

	def focused_element?(owner:, name:)
		@runtime.focused_element?(owner:, name:)
	end

	def copy_to_clipboard(text)
		@clipboard = text.to_s.dup
		write_osc52_copy(@clipboard)
		nil
	end

	def paste_from_clipboard
		@clipboard.dup
	end

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
		@last_frame_duration = nil
		@last_render_duration = nil
		@last_draw_duration = nil
		@render_request_version = 0
		@rendered_version = 0
		@render_signal_pending = false
		@event_queue = Queue.new
		@pending_mouse_move_raw = nil
		@mouse_move_signal_pending = false
		@paste_mode = false
		@paste_buffer = +""
		@input_buffer = +""
		@mouse_capture_ref = nil
		previous_lines = []
		last_size = nil
		previous_winch_handler = nil
		previous_int_handler = nil

		enter_terminal_session
		previous_winch_handler = install_winch_handler
		previous_int_handler = install_int_handler
		start_input_thread
		request_render!

		while @running
			event = @event_queue.pop
			drain_pending_events(initial_event: event)
			next unless @running
			next unless render_requested?

			sleep_until_frame_due

			frame_started_at = monotonic_time
			target_render_version = @queue_mutex.synchronize { @render_request_version }
			rows, cols = terminal_size
			@rows = rows
			@cols = cols
			size = [rows, cols]
			resized = size != last_size
			last_size = size

			dt = frame_delta(frame_started_at)
			update(dt)
			draw_started_at = monotonic_time
			render_started_at = monotonic_time

			current_lines = render_lines(width: cols, height: rows)
			@last_render_duration = monotonic_time - render_started_at
			output = if resized || previous_lines.empty?
				@differ.full(current_lines, clear: true)
			else
				@differ.diff(previous_lines, current_lines)
			end

			unless output.empty?
				@stdout.write(output)
				@stdout.flush
			end

			@last_draw_duration = monotonic_time - draw_started_at

			previous_lines = current_lines
			@last_frame_duration = monotonic_time - frame_started_at
			@last_render_at = frame_started_at

			@queue_mutex.synchronize do
				@rendered_version = target_render_version
				@render_signal_pending = false

				if @render_request_version > @rendered_version
					@render_signal_pending = true
					@event_queue << :render
				end
			end
		end
	rescue Interrupt
		@running = false
	ensure
		restore_winch_handler(previous_winch_handler)
		restore_int_handler(previous_int_handler)
		stop_input_thread
		disable_input_mode
		close_input_io
		exit_terminal_session
	end

	def stop
		@running = false
		@event_queue << :stop
	end

	def request_render!
		@queue_mutex.synchronize do
			@render_request_version += 1
			next if @render_signal_pending

			@render_signal_pending = true
			@event_queue << :render
		end

		nil
	end

	def update(_dt)
	end

	private def render_lines(width:, height:)
		previous_focused_id = @runtime.focused_id
		@runtime.begin_frame!
		tree = call(Phlex::TUI::Tree.new, context: self)
		renderer = Phlex::TUI::Render.new(tree, width:, height:)
		lines = renderer.render_canvas.styled_lines
		@runtime.finalize_frame!
		cleanup_hover_target
		dispatch_focus_transition(previous_focused_id, @runtime.focused_id)
		lines
	end

	private def render_requested?
		@queue_mutex.synchronize { @render_request_version > @rendered_version }
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
		@stdout.write(ENABLE_MOUSE_TRACKING)
		@stdout.write(ENABLE_BRACKETED_PASTE)
		@stdout.write("\e[H\e[2J")
		@stdout.flush
	end

	private def exit_terminal_session
		return unless @session_active

		@stdout.write(RESET_STYLE)
		@stdout.write(DISABLE_MOUSE_TRACKING)
		@stdout.write(DISABLE_BRACKETED_PASTE)
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

	private def install_int_handler
		Signal.trap("INT") { stop }
	rescue ArgumentError, ThreadError
		nil
	end

	private def restore_winch_handler(handler)
		return unless handler

		Signal.trap("WINCH", handler)
	rescue ArgumentError, ThreadError
		nil
	end

	private def restore_int_handler(handler)
		return unless handler

		Signal.trap("INT", handler)
	rescue ArgumentError, ThreadError
		nil
	end

	private def start_input_thread
		console = open_input_io
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

	private def open_input_io
		return @input_io if @input_io
		if $stdin.tty?
			@input_io = $stdin
			return @input_io
		end

		console = IO.console
		if console&.tty?
			@input_io = console
			return @input_io
		end

		@input_io = File.open("/dev/tty", "r+")
	rescue SystemCallError
		nil
	end

	private def close_input_io
		io = @input_io
		@input_io = nil
		return unless io

		io.close unless io.closed? || io.equal?(IO.console) || io.equal?($stdin)
	rescue IOError
		nil
	end

	private def read_key(io)
		if @input_buffer.empty?
			return nil unless io.wait_readable(0.05)
			chunk = io.read_nonblock(4096, exception: false)
			return nil if chunk == :wait_readable || chunk.nil?
			@input_buffer << chunk
		end

		first_byte = @input_buffer.getbyte(0)

		if first_byte != 27
			if first_byte < 0x80
				key = @input_buffer.byteslice(0, 1)
				@input_buffer.slice!(0, 1)
				return key.force_encoding(Encoding::UTF_8)
			end

			expected = utf8_sequence_length(first_byte)

			while @input_buffer.bytesize < expected
				return nil unless io.wait_readable(0.01)
				chunk = io.read_nonblock(1024, exception: false)
				return nil if chunk == :wait_readable || chunk.nil?
				@input_buffer << chunk
			end

			key = @input_buffer.byteslice(0, expected)
			@input_buffer.slice!(0, expected)
			text = key.force_encoding(Encoding::UTF_8)
			return text.valid_encoding? ? text : text.scrub
		end

		len = escape_sequence_length(@input_buffer)

		if len
			key = @input_buffer.byteslice(0, len)
			@input_buffer.slice!(0, len)
			return key.force_encoding(Encoding::UTF_8)
		end

		if io.wait_readable(0.01)
			chunk = io.read_nonblock(1024, exception: false)
			if chunk != :wait_readable && !chunk.nil?
				@input_buffer << chunk

				len = escape_sequence_length(@input_buffer)
				if len
					key = @input_buffer.byteslice(0, len)
					@input_buffer.slice!(0, len)
					return key.force_encoding(Encoding::UTF_8)
				end
			end
		end

		if @input_buffer.bytesize == 1
			key = @input_buffer.byteslice(0, 1)
			@input_buffer.slice!(0, 1)
			return key.force_encoding(Encoding::UTF_8)
		end

		key = @input_buffer.dup
		@input_buffer.clear
		key.force_encoding(Encoding::UTF_8)
	end

	private def escape_sequence_length(buffer)
		return nil if buffer.bytesize < 2

		if buffer.start_with?("\e[")
			match = %r{\A\e\[[0-?]*[ -/]*[@-~]}.match(buffer)
			return match ? match[0].bytesize : nil
		end

		if buffer.start_with?("\eO")
			return (buffer.bytesize >= 3) ? 3 : nil
		end

		2
	end

	private def utf8_sequence_length(first_byte)
		if (first_byte & 0b1110_0000) == 0b1100_0000
			2
		elsif (first_byte & 0b1111_0000) == 0b1110_0000
			3
		elsif (first_byte & 0b1111_1000) == 0b1111_0000
			4
		else
			1
		end
	end

	private def enable_input_mode
		return true if @input_mode_active
		io = open_input_io
		return false unless io

		@input_mode_saved = read_stty_mode(io)
		return false if @input_mode_saved.empty?

		@input_mode_active = system("stty", "-icanon", "-echo", "isig", "min", "1", "time", "0", in: io)
	rescue SystemCallError
		false
	end

	private def disable_input_mode
		return unless @input_mode_active
		return unless @input_mode_saved && !@input_mode_saved.empty?
		io = @input_io
		return unless io

		system("stty", @input_mode_saved, in: io)
	ensure
		@input_mode_saved = nil
		@input_mode_active = false
	end

	private def read_stty_mode(io)
		IO.popen(["stty", "-g"], in: io, &:read).to_s.chomp
	rescue SystemCallError
		""
	end

	private def enqueue_event(event)
		if Array === event && event[0] == :input && String === event[1] && fast_mouse_move_input?(event[1])
			@queue_mutex.synchronize do
				@pending_mouse_move_raw = event[1]
				next if @mouse_move_signal_pending

				@mouse_move_signal_pending = true
				@event_queue << :mouse_move_pending
			end
			return
		end

		@event_queue << event
	end

	private def handle_event(event)
		case event
		when :render
			nil
		when :mouse_move_pending
			raw_key = nil
			@queue_mutex.synchronize do
				raw_key = @pending_mouse_move_raw
				@pending_mouse_move_raw = nil
				@mouse_move_signal_pending = false
			end
			handle_input(raw_key) if raw_key
		when :resize
			request_render!
		when :stop
			nil
		when Array
			handle_input(event[1]) if event[0] == :input && String === event[1]
		end
	end

	private def drain_pending_events(initial_event: nil)
		pending_wheel_event = nil
		pending_mouse_move_event = nil

		handle_queued_event = lambda do |event|
			mouse_event = input_mouse_event(event)
			if mouse_event
				case mouse_event
					in Phlex::TUI::MouseMoveEvent
						pending_mouse_move_event = mouse_event
					in Phlex::TUI::MouseWheelEvent
						flush_pending_mouse_move_event(pending_mouse_move_event)
						pending_mouse_move_event = nil
						pending_wheel_event = coalesce_wheel_event(pending_wheel_event, mouse_event)
					else
						flush_pending_mouse_move_event(pending_mouse_move_event)
						pending_mouse_move_event = nil
						flush_pending_wheel_event(pending_wheel_event)
						pending_wheel_event = nil
						handle_mouse_event(mouse_event)
				end
				return
			end

			flush_pending_mouse_move_event(pending_mouse_move_event)
			pending_mouse_move_event = nil
			flush_pending_wheel_event(pending_wheel_event)
			pending_wheel_event = nil
			handle_event(event)
		end

		handle_queued_event.call(initial_event) if initial_event

		loop do
			event = @event_queue.pop(true)
			handle_queued_event.call(event)
			break unless @running
		end
	rescue ThreadError
		flush_pending_mouse_move_event(pending_mouse_move_event)
		flush_pending_wheel_event(pending_wheel_event)
		nil
	end

	private def flush_pending_mouse_move_event(event)
		return unless event

		handle_mouse_event(event)
	end

	private def input_mouse_event(event)
		return nil unless Array === event
		return nil unless event[0] == :input
		return nil unless String === event[1]

		parse_mouse_event(event[1])
	end

	private def wheel_event_input?(event)
		return false unless Array === event
		return false unless event[0] == :input
		return false unless String === event[1]

		Phlex::TUI::MouseWheelEvent === parse_mouse_event(event[1])
	end

	private def coalesce_wheel_event(current, incoming)
		return incoming unless current

		current_delta = current.delta_y
		incoming_delta = incoming.delta_y

		if Integer === current_delta && Integer === incoming_delta
			if (current_delta < 0) != (incoming_delta < 0)
				incoming
			else
				incoming.with_delta(current_delta + incoming_delta)
			end
		else
			incoming
		end
	end

	private def flush_pending_wheel_event(event)
		return unless event

		handle_mouse_event(event)
	end

	private def handle_input(raw_key)
		if @paste_mode
			if raw_key == BRACKETED_PASTE_END
				dispatch_text_input(@paste_buffer)
				@paste_buffer = +""
				@paste_mode = false
			else
				@paste_buffer << raw_key
			end

			return
		end

		if raw_key == BRACKETED_PASTE_START
			@paste_mode = true
			@paste_buffer = +""
			return
		end

		if raw_key == "\u0003"
			event = Phlex::TUI::KeyDownEvent.new(key: :ctrl_c, raw: raw_key)
			event = @runtime.dispatch_bubbled(@runtime.focused_id, event)
			unless event&.default_prevented?
				stop
			end
			return
		end

		mouse_event = parse_mouse_event(raw_key)
		if mouse_event
			handle_mouse_event(mouse_event)
			return
		end

		key = normalize_key(raw_key)
		event = Phlex::TUI::KeyDownEvent.new(key:, raw: raw_key)

		event = @runtime.dispatch_bubbled(@runtime.focused_id, event)

		if text_input?(raw_key)
			dispatch_text_input(raw_key) unless event&.default_prevented?
			return
		end

		if navigation_key?(key)
			handle_navigation_key(key) unless event&.default_prevented?
			nil
		end
	end

	private def text_input?(raw_key)
		return false if raw_key.empty?
		return false if raw_key.start_with?("\e")
		return false if raw_key == "\n" || raw_key == "\r" || raw_key == "\t"

		text = raw_key.dup
		text = text.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
		return false unless text.valid_encoding?

		text.each_codepoint do |codepoint|
			return false if codepoint < 32 || codepoint == 127
		end

		true
	end

	private def dispatch_text_input(text)
		return if text.nil? || text.empty?

		normalized = text.dup
		normalized = normalized.force_encoding(Encoding::UTF_8) unless normalized.encoding == Encoding::UTF_8
		normalized = normalized.scrub unless normalized.valid_encoding?

		event = Phlex::TUI::TextInputEvent.new(text: normalized, raw: normalized)
		@runtime.dispatch_bubbled(@runtime.focused_id, event)
	end

	private def navigation_key?(key)
		key == :right || key == :down || key == :left || key == :up
	end

	private def handle_navigation_key(key)
		previous_focused_id = @runtime.focused_id
		focus_changed = case key
		when :right, :down
			@runtime.focus_next!
		when :left, :up
			@runtime.focus_previous!
		end

		return unless focus_changed

		dispatch_focus_transition(previous_focused_id, @runtime.focused_id)
	end

	private def dispatch_focus_transition(previous_focused_id, current_focused_id)
		return if previous_focused_id == current_focused_id

		@runtime.dispatch(previous_focused_id, Phlex::TUI::BlurEvent.new) if previous_focused_id
		@runtime.dispatch(current_focused_id, Phlex::TUI::FocusEvent.new) if current_focused_id
	end

	private def normalize_key(raw_key)
		named = KEY_NAMES[raw_key]
		return named if named

		if raw_key.start_with?("\e\e[")
			case raw_key[2..]
			in "[D"
				return :alt_left
			in "[C"
				return :alt_right
			in "[A"
				return :alt_up
			in "[B"
				return :alt_down
			end
		end

		if raw_key.bytesize == 1
			char = raw_key.downcase
			if /\A[[:alnum:]]\z/.match?(char)
				return char.to_sym
			end
		end

		:unknown
	end

	private def parse_mouse_event(key)
		match = /\A\e\[<(\d+);(\d+);(\d+)([Mm])\z/.match(key)
		return nil unless match

		code = match[1].to_i
		col = match[2].to_i - 1
		row = match[3].to_i - 1
		action = match[4]

		is_wheel = action == "M" && (code & 0b1_000000) != 0
		is_move = action == "M" && (code & 0b100000) != 0

		delta_y = if is_wheel
			((code & 0b1) == 0) ? -1 : 1
		end

		button = (code & 0b11)
		shift = (code & 0b100) != 0
		alt = (code & 0b1000) != 0
		ctrl = (code & 0b1_0000) != 0

		if is_wheel
			Phlex::TUI::MouseWheelEvent.new(delta_y:, col:, row:, button:, shift:, alt:, ctrl:, raw: key)
		elsif is_move
			Phlex::TUI::MouseMoveEvent.new(col:, row:, button:, shift:, alt:, ctrl:, raw: key)
		elsif action == "M"
			Phlex::TUI::MouseDownEvent.new(col:, row:, button:, shift:, alt:, ctrl:, raw: key)
		else
			Phlex::TUI::MouseUpEvent.new(col:, row:, button:, shift:, alt:, ctrl:, raw: key)
		end
	end

	private def fast_mouse_move_input?(raw_key)
		match = /\A\e\[<(\d+);\d+;\d+M\z/.match(raw_key)
		return false unless match

		code = match[1].to_i
		return false if (code & 0b1_000000) != 0

		(code & 0b100000) != 0
	end

	private def handle_mouse_event(mouse_event)
		col = mouse_event.col
		row = mouse_event.row
		previous_col = @last_pointer_col
		previous_row = @last_pointer_row

		if Integer === col && Integer === row
			@last_pointer_col = col
			@last_pointer_row = row
		end

		hit_target_id = @runtime.hit_test(col:, row:)
		capture_id = @mouse_capture_ref
		if capture_id && !@runtime.event_for(capture_id)
			@mouse_capture_ref = nil
			capture_id = nil
		end

		target_id = case mouse_event
		in Phlex::TUI::MouseDownEvent
			hit_target_id
		in Phlex::TUI::MouseMoveEvent | Phlex::TUI::MouseUpEvent
			capture_id || hit_target_id
		else
			hit_target_id
		end

		if Phlex::TUI::MouseWheelEvent === mouse_event && hit_target_id.nil?
			last_col = previous_col
			last_row = previous_row
			if Integer === last_col && Integer === last_row
				hit_target_id = @runtime.hit_test(col: last_col, row: last_row)
			end

			hit_target_id ||= @hovered_path.first
			target_id = hit_target_id
		end

		dispatch_hover_transition(@runtime.event_path_for(hit_target_id))
		unless target_id
			@mouse_capture_ref = nil if Phlex::TUI::MouseUpEvent === mouse_event
			return
		end

		@runtime.dispatch_bubbled(target_id, mouse_event)

		case mouse_event
		in Phlex::TUI::MouseDownEvent
			@mouse_capture_ref = target_id
		in Phlex::TUI::MouseUpEvent
			@mouse_capture_ref = nil
		else
			nil
		end
	end

	private def dispatch_hover_transition(next_path)
		previous_path = @hovered_path
		next_path ||= []
		return if previous_path == next_path

		common_tail = common_tail_length(previous_path, next_path)
		leaving_ids = previous_path[0...(previous_path.length - common_tail)] || []
		entering_ids = next_path[0...(next_path.length - common_tail)] || []

		leaving_ids.each do |id|
			@runtime.dispatch(id, Phlex::TUI::MouseLeaveEvent.new)
		end

		entering_ids.each do |id|
			@runtime.dispatch(id, Phlex::TUI::MouseEnterEvent.new)
		end

		@hovered_path = next_path
	end

	private def cleanup_hover_target
		return if @hovered_path.empty?

		all_present = @hovered_path.all? { |id| @runtime.event_for(id) }
		return if all_present

		@hovered_path.each do |id|
			@runtime.dispatch(id, Phlex::TUI::MouseLeaveEvent.new)
		end

		@hovered_path = []
	end

	private def common_tail_length(left, right)
		length = 0
		left_index = left.length - 1
		right_index = right.length - 1

		while left_index >= 0 && right_index >= 0 && left[left_index] == right[right_index]
			length += 1
			left_index -= 1
			right_index -= 1
		end

		length
	end

	private def write_osc52_copy(text)
		return unless @session_active
		return if text.empty?

		encoded = Base64.strict_encode64(text)
		@stdout.write("\e]52;c;#{encoded}\a")
		@stdout.flush
	rescue IOError, SystemCallError
		nil
	end
end
