# frozen_string_literal: true

require "io/console"

class Phlex::TUI::App < Phlex::TUI
	BRACKETED_PASTE_START = "\e[200~"
	BRACKETED_PASTE_END = "\e[201~"

	attr_reader :rows
	attr_reader :cols
	attr_reader :last_frame_duration
	attr_reader :last_render_duration
	attr_reader :last_draw_duration
	attr_reader :component_tick_dt

	def runtime
		@runtime ||= Phlex::TUI::Runtime.new
	end

	def focus_element(owner:, name:)
		ensure_defaults!
		element_id = runtime.element_ref(owner:, name:)
		previous_focused_id = runtime.focused_id
		changed = runtime.focus!(element_id)
		return false unless changed

		dispatch_focus_transition(previous_focused_id, runtime.focused_id)
		request_render!
		true
	end

	def focused_element?(owner:, name:)
		ensure_defaults!
		runtime.focused_element?(owner:, name:)
	end

	def copy_to_clipboard(text)
		ensure_defaults!
		@clipboard = text.to_s.dup
		terminal_session.write_osc52_copy(@clipboard)
		nil
	end

	def paste_from_clipboard
		ensure_defaults!
		(@clipboard || +"").dup
	end

	def app
		self
	end

	def register_rendered_component(component)
		ensure_defaults!
		@rendered_components ||= []
		@rendered_component_set ||= {}.compare_by_identity
		return nil if @rendered_component_set[component]

		@rendered_component_set[component] = true
		@rendered_components << component
		nil
	end

	def start(fps: nil)
		ensure_defaults!
		@stdout ||= $stdout

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
		@mouse_capture_ref = nil
		@component_tick_dt = 0.0
		@rendered_components.clear
		@rendered_component_set.clear
		previous_lines = []
		last_size = nil
		previous_winch_handler = nil
		previous_int_handler = nil

		@terminal_session = Phlex::TUI::TerminalSession.new(stdout: @stdout)
		@terminal_session.enter!
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
			@component_tick_dt = dt
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
		terminal_session.disable_input_mode
		terminal_session.close_input_io
		terminal_session.exit!
	end

	def stop
		ensure_defaults!
		@event_queue ||= Queue.new
		@running = false
		@event_queue << :stop
	end

	def request_render!
		ensure_defaults!
		@queue_mutex ||= Mutex.new
		@event_queue ||= Queue.new
		@render_request_version ||= 0
		@render_signal_pending ||= false
		@rendered_version ||= 0

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
		ensure_defaults!
		previous_focused_id = runtime.focused_id
		runtime.begin_frame!
		@rendered_components.clear
		@rendered_component_set.clear
		tree = call(Phlex::TUI::Tree.new, context: self)
		renderer = Phlex::TUI::Render.new(tree, width:, height:)
		lines = renderer.render_canvas.styled_lines
		runtime.finalize_frame!
		cleanup_hover_target
		dispatch_focus_transition(previous_focused_id, runtime.focused_id)
		tick_rendered_components!
		lines
	end

	private def tick_rendered_components!
		dt = @component_tick_dt
		components = @rendered_components
		i = 0
		max = components.length

		while i < max
			components[i].tick(dt)
			i += 1
		end
	end

	private def render_requested?
		ensure_defaults!
		@queue_mutex.synchronize { @render_request_version > @rendered_version }
	end

	private def terminal_size
		console = @stdout.respond_to?(:winsize) ? @stdout : IO.console
		rows, cols = console&.winsize

		rows = 24 unless Integer === rows && rows.positive?
		cols = 80 unless Integer === cols && cols.positive?

		[rows, cols]
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
		console = terminal_session.open_input_io
		return unless console&.tty?
		return unless terminal_session.enable_input_mode

		@input_thread = Thread.new do
			while @running
				key = @input_decoder.read_key(console)
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

	private def enqueue_event(event)
		if Array === event && event[0] == :input && String === event[1] && @input_decoder.fast_mouse_move_input?(event[1])
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

		@input_decoder.parse_mouse_event(event[1])
	end

	private def wheel_event_input?(event)
		return false unless Array === event
		return false unless event[0] == :input
		return false unless String === event[1]

		Phlex::TUI::MouseWheelEvent === @input_decoder.parse_mouse_event(event[1])
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
		ensure_defaults!
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
			event = dispatch_key_down(:ctrl_c, raw_key)
			dispatch_key_up(:ctrl_c, raw_key)
			stop unless event&.default_prevented?
			return
		end

		mouse_event = @input_decoder.parse_mouse_event(raw_key)
		if mouse_event
			handle_mouse_event(mouse_event)
			return
		end

		key = @input_decoder.normalize_key(raw_key)
		event = dispatch_key_down(key, raw_key)

		if @input_decoder.text_input?(raw_key)
			dispatch_text_input(raw_key) unless event&.default_prevented?
			dispatch_key_up(key, raw_key)
			return
		end

		if navigation_key?(key)
			handle_navigation_key(key) unless event&.default_prevented?
		end

		dispatch_key_up(key, raw_key)
		nil
	end

	private def dispatch_key_down(key, raw_key)
		event = Phlex::TUI::KeyDownEvent.new(key:, raw: raw_key)
		runtime.dispatch_bubbled(runtime.focused_id, event)
	end

	private def dispatch_key_up(key, raw_key)
		event = Phlex::TUI::KeyUpEvent.new(key:, raw: raw_key)
		runtime.dispatch_bubbled(runtime.focused_id, event)
	end

	private def dispatch_text_input(text)
		return if text.nil? || text.empty?

		normalized = text.dup
		normalized = normalized.force_encoding(Encoding::UTF_8) unless normalized.encoding == Encoding::UTF_8
		normalized = normalized.scrub unless normalized.valid_encoding?

		event = Phlex::TUI::TextInputEvent.new(text: normalized, raw: normalized)
		runtime.dispatch_bubbled(runtime.focused_id, event)
	end

	private def navigation_key?(key)
		key == :right || key == :down || key == :left || key == :up
	end

	private def handle_navigation_key(key)
		previous_focused_id = runtime.focused_id
		focus_changed = case key
		when :right, :down
			runtime.focus_next!
		when :left, :up
			runtime.focus_previous!
		end

		return unless focus_changed

		dispatch_focus_transition(previous_focused_id, runtime.focused_id)
	end

	private def dispatch_focus_transition(previous_focused_id, current_focused_id)
		return if previous_focused_id == current_focused_id

		runtime.dispatch(previous_focused_id, Phlex::TUI::BlurEvent.new) if previous_focused_id
		runtime.dispatch(current_focused_id, Phlex::TUI::FocusEvent.new) if current_focused_id
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

		hit_target_id = runtime.hit_test(col:, row:)
		capture_id = @mouse_capture_ref
		if capture_id && !runtime.event_for(capture_id)
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
				hit_target_id = runtime.hit_test(col: last_col, row: last_row)
			end

			hit_target_id ||= @hovered_path.first
			target_id = hit_target_id
		end

		dispatch_hover_transition(runtime.event_path_for(hit_target_id))
		unless target_id
			@mouse_capture_ref = nil if Phlex::TUI::MouseUpEvent === mouse_event
			return
		end

		runtime.dispatch_bubbled(target_id, mouse_event)

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
			runtime.dispatch(id, Phlex::TUI::MouseLeaveEvent.new)
		end

		entering_ids.each do |id|
			runtime.dispatch(id, Phlex::TUI::MouseEnterEvent.new)
		end

		@hovered_path = next_path
	end

	private def cleanup_hover_target
		return if @hovered_path.empty?

		all_present = @hovered_path.all? { |id| runtime.event_for(id) }
		return if all_present

		@hovered_path.each do |id|
			runtime.dispatch(id, Phlex::TUI::MouseLeaveEvent.new)
		end

		@hovered_path = []
	end

	private def common_tail_length(left, right)
		left ||= []
		right ||= []
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

	private def terminal_session
		@terminal_session ||= Phlex::TUI::TerminalSession.new(stdout: @stdout || $stdout)
	end

	private def ensure_defaults!
		@differ ||= Phlex::TUI::FrameDiffer.new
		@runtime ||= Phlex::TUI::Runtime.new
		@input_decoder ||= Phlex::TUI::InputDecoder.new
		@rows ||= 24
		@cols ||= 80
		@render_request_version ||= 0
		@rendered_version ||= 0
		@render_signal_pending = false if @render_signal_pending.nil?
		@event_queue ||= Queue.new
		@queue_mutex ||= Mutex.new
		@pending_mouse_move_raw = nil if @pending_mouse_move_raw.nil?
		@mouse_move_signal_pending = false if @mouse_move_signal_pending.nil?
		@hovered_path ||= []
		@mouse_capture_ref = nil if @mouse_capture_ref.nil?
		@paste_mode = false if @paste_mode.nil?
		@paste_buffer ||= +""
		@clipboard ||= +""
		@component_tick_dt ||= 0.0
		@rendered_components ||= []
		@rendered_component_set ||= {}.compare_by_identity
		nil
	end
end
