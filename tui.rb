#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "phlex"

class DemoTUIApp < Phlex::TUI::App
	def initialize(...)
		super
		@elapsed = 0.0
		@frames = 0
		@fps = 0.0
	end

	def update(dt)
		@elapsed += dt
		@frames += 1
		if dt.positive?
			instant = 1.0 / dt
			@fps = (@fps * 0.9) + (instant * 0.1)
		end
	end

	def view_template
		box(width: :grow, height: :grow, border: :rounded, padding: 1, gap: 1) do
			paragraph("Phlex::TUI Demo", bold: true)
			paragraph("Unlimited render loop with row-level frame diffing")
			paragraph("Resize terminal to trigger full redraw. Press Ctrl+C to exit.", color: :bright_black)
			hr(border: :thin)

			paragraph("fps=#{format('%.1f', @fps)}  frames=#{@frames}  time=#{format('%.2f', @elapsed)}s  size=#{cols}x#{rows}")
		end
	end
end

DemoTUIApp.new.start
