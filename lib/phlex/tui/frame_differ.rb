# frozen_string_literal: true

class Phlex::TUI::FrameDiffer
	CLEAR_SCREEN = "\e[2J"
	HOME = "\e[H"

	def full(lines, clear: true)
		buffer = +""
		buffer << HOME
		buffer << CLEAR_SCREEN if clear

		lines.each_with_index do |line, index|
			buffer << line
			buffer << "\n" if index < (lines.length - 1)
		end

		buffer
	end

	def diff(previous_lines, current_lines)
		buffer = +""
		line_count = [previous_lines.length, current_lines.length].max

		line_count.times do |index|
			previous_line = previous_lines[index] || ""
			current_line = current_lines[index] || ""
			next if previous_line == current_line

			buffer << "\e[#{index + 1};1H"
			buffer << current_line
		end

		buffer
	end
end
