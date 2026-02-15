# frozen_string_literal: true

module Phlex::TUI::Terminal
	extend self

	# Maps color names to their 256-color palette index
	PALETTE_COLORS = {
		black: 0,
		red: 1,
		green: 2,
		yellow: 3,
		blue: 4,
		magenta: 5,
		cyan: 6,
		white: 7,
		bright_black: 8,
		bright_red: 9,
		bright_green: 10,
		bright_yellow: 11,
		bright_blue: 12,
		bright_magenta: 13,
		bright_cyan: 14,
		bright_white: 15,
	}.freeze

	FALLBACK_RGB_COLORS = {
		foreground: [229, 229, 229],
		background: [0, 0, 0],
		black: [0, 0, 0],
		red: [205, 0, 0],
		green: [0, 205, 0],
		yellow: [205, 205, 0],
		blue: [0, 0, 238],
		magenta: [205, 0, 205],
		cyan: [0, 205, 205],
		white: [229, 229, 229],
		bright_black: [127, 127, 127],
		bright_red: [255, 0, 0],
		bright_green: [0, 255, 0],
		bright_yellow: [255, 255, 0],
		bright_blue: [92, 92, 255],
		bright_magenta: [255, 0, 255],
		bright_cyan: [0, 255, 255],
		bright_white: [255, 255, 255],
	}.freeze

	RGB_PATTERN = %r{rgb:(?<r>[0-9a-f]+)/(?<g>[0-9a-f]+)/(?<b>[0-9a-f]+)}i

	TERMINAL_COLOR_CACHE = {}
	TRUECOLOR = Object.new
	COLOR_MODE = Object.new

	def color(color_name)
		TERMINAL_COLOR_CACHE[color_name] ||= query_color(color_name) || FALLBACK_RGB_COLORS[color_name]
	end

	def truecolor?
		cached = TERMINAL_COLOR_CACHE[TRUECOLOR]
		return cached unless cached.nil?

		colorterm = ENV["COLORTERM"].to_s.downcase
		term = ENV["TERM"].to_s.downcase

		TERMINAL_COLOR_CACHE[TRUECOLOR] = colorterm.include?("truecolor") || colorterm.include?("24bit") || term.include?("truecolor") || term.include?("direct")
	end

	def color_mode
		cached = TERMINAL_COLOR_CACHE[COLOR_MODE]
		return cached unless cached.nil?

		r, g, b = color(:background)
		brightness = (r * 299) + (g * 587) + (b * 114)
		TERMINAL_COLOR_CACHE[COLOR_MODE] = (brightness >= (128_000)) ? :light : :dark
	end

	def light_mode?
		color_mode == :light
	end

	def dark_mode?
		color_mode == :dark
	end

	def query_color(color_name)
		osc_sequence = case color_name
		when :foreground then "\e]10;?\e\\"
		when :background then "\e]11;?\e\\"
		else
			color_index = PALETTE_COLORS[color_name]
			return nil unless color_index
			"\e]4;#{color_index};?\e\\"
		end

		response = with_raw_terminal { query_osc(osc_sequence) }
		parse_rgb_response(response)
	end

	private def with_raw_terminal
		return nil unless STDIN.tty? && STDOUT.tty?

		old_stty = `stty -g`.chomp
		system("stty", "raw", "-echo", "min", "0", "time", "10")
		yield
	ensure
		system("stty", old_stty) if old_stty
	end

	private def query_osc(sequence)
		print sequence
		STDOUT.flush

		response = +""
		while (char = STDIN.getc)
			response << char
			# Response ends with BEL (\a) or ST (\e\\)
			break if char == "\a" || (char == "\\" && response[-2] == "\e")
		end
		response
	end

	private def parse_rgb_response(response)
		return nil unless (match = RGB_PATTERN.match(response))

		[
			scale_component(match[:r]),
			scale_component(match[:g]),
			scale_component(match[:b]),
		]
	end

	private def scale_component(value)
		max = (16 ** value.length) - 1
		return 0 if max <= 0

		((value.to_i(16) * 255.0) / max).round
	end
end
