#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"

plain = ARGV.delete("--plain")
show_spaces = ARGV.delete("--show-spaces")
show_ruler = ARGV.delete("--ruler")

[:red, 0.5]
[123, 123, 123, 0.123]

class Demo < Phlex::TUI
	def view_template
		vstack(padding: [1, 2]) do
			table(border: :rounded) do
				row(border: { bottom: :thin }, bold: true) do
					col { "Language" }
					col { "Creator" }
					col { "Year" }
					col { "Typing" }
				end

				row do
					col { "Ruby" }
					col { "Matz" }
					col { "1995" }
					col { "Dynamic" }
				end

				row do
					col { "Rust" }
					col { "Graydon Hoare" }
					col { "2010" }
					col { "Static" }
				end

				row do
					col { "Elixir" }
					col { "Jose Valim" }
					col { "2011" }
					col { "Dynamic" }
				end

				row do
					col { "Go" }
					col { "Rob Pike et al." }
					col { "2009" }
					col { "Static" }
				end
			end
		end
	end

	def col(**, &)
		super(padding: [0, 1], **, &)
	end
end

tree = Demo.new.call
output = Phlex::TUI::Render.new(tree, width: :fit, height: :fit).call

if plain
	output = output.gsub(/\e\[[0-9;]*m/, "")
	if show_spaces
		output = output.lines.map { |line| line.chomp.gsub(" ", "·") }.join("\n")
	end

	if show_ruler
		lines = output.lines.map(&:chomp)
		width = lines.map(&:length).max || 0
		ones = (0...width).map { |i| i % 10 }.join
		tens = (0...width).map { |i| (i % 10 == 0) ? ((i / 10) % 10).to_s : " " }.join

		output = [
			"    #{tens}",
			"    #{ones}",
			*lines.each_with_index.map { |line, index| format("%3d %s", index, line) },
		].join("\n")
	end
end

puts output

# canvas = Phlex::TUI::Canvas.new(width: 10, height: 3)

# canvas.draw_vertical_line(0, 3, height: 3, style: :thick)
# canvas.draw_horizontal_line(1, 0, width: 7, style: :thin)

# puts canvas

# Horizonal = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
# Vertical = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

# Shade = {
# 	light: "░",
# 	medium: "▒",
# 	dark: "▓",
# }

# module Keyframes
# 	Snake = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
# 	Ellipsis = [".  ", ".. ", "..."]
# 	Jump = ["▖", "▘", "▝", "▗"]
#   Dots = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
# 	Bounce = ["▁", "▂", "▃", "▄", "▅", "▆", "█", "▀", "█", "▆", "▅", "▄", "▃", "▂", "▁"]
# end
