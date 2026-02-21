# frozen_string_literal: true

class Phlex::TUI::InputDecoder
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

	def initialize
		@input_buffer = +""
	end

	def read_key(io)
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

	def normalize_key(raw_key)
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

	def parse_mouse_event(key)
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

	def text_input?(raw_key)
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

	def fast_mouse_move_input?(raw_key)
		match = /\A\e\[<(\d+);\d+;\d+M\z/.match(raw_key)
		return false unless match

		code = match[1].to_i
		return false if (code & 0b1_000000) != 0

		(code & 0b100000) != 0
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
end
