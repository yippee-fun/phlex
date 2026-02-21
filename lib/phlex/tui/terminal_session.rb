# frozen_string_literal: true

require "base64"

class Phlex::TUI::TerminalSession
	CURSOR_HIDE = "\e[?25l"
	CURSOR_SHOW = "\e[?25h"
	ENTER_ALT_SCREEN = "\e[?1049h"
	EXIT_ALT_SCREEN = "\e[?1049l"
	RESET_STYLE = "\e[0m"
	ENABLE_MOUSE_TRACKING = "\e[?1000h\e[?1003h\e[?1006h"
	DISABLE_MOUSE_TRACKING = "\e[?1006l\e[?1003l\e[?1000l"
	ENABLE_BRACKETED_PASTE = "\e[?2004h"
	DISABLE_BRACKETED_PASTE = "\e[?2004l"

	def initialize(stdout:)
		@stdout = stdout
		@session_active = false
		@input_io = nil
		@input_mode_saved = nil
		@input_mode_active = false
	end

	attr_reader :stdout

	def enter!
		return unless @stdout

		@session_active = true
		@stdout.write(ENTER_ALT_SCREEN)
		@stdout.write(CURSOR_HIDE)
		@stdout.write(ENABLE_MOUSE_TRACKING)
		@stdout.write(ENABLE_BRACKETED_PASTE)
		@stdout.write("\e[H\e[2J")
		@stdout.flush
	end

	def exit!
		return unless @session_active
		return unless @stdout

		@stdout.write(RESET_STYLE)
		@stdout.write(DISABLE_MOUSE_TRACKING)
		@stdout.write(DISABLE_BRACKETED_PASTE)
		@stdout.write(CURSOR_SHOW)
		@stdout.write(EXIT_ALT_SCREEN)
		@stdout.flush
		@session_active = false
	end

	def write_osc52_copy(text)
		return unless @session_active
		return unless @stdout
		return if text.empty?

		encoded = Base64.strict_encode64(text)
		@stdout.write("\e]52;c;#{encoded}\a")
		@stdout.flush
	rescue IOError, SystemCallError
		nil
	end

	def open_input_io
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

	def close_input_io
		io = @input_io
		@input_io = nil
		return unless io

		io.close unless io.closed? || io.equal?(IO.console) || io.equal?($stdin)
	rescue IOError
		nil
	end

	def enable_input_mode
		return true if @input_mode_active
		io = open_input_io
		return false unless io

		@input_mode_saved = read_stty_mode(io)
		return false if @input_mode_saved.empty?

		@input_mode_active = system("stty", "-icanon", "-echo", "isig", "min", "1", "time", "0", in: io)
	rescue SystemCallError
		false
	end

	def disable_input_mode
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
end
