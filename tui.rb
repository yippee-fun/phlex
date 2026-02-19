#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "phlex"

class ScrollerShowcase < Phlex::TUI
	def initialize
		@scroller = Phlex::Tux::Scroller.new(
			border: :rounded,
			padding: [0, 1],
			height: 14,
			width: :grow
		)
	end

	def view_template
		box(width: :grow, height: :grow, border: :rounded, padding: 1, gap: 1) do
			paragraph("Phlex::Tux::Scroller Demo", bold: true)
			paragraph("Use arrow keys, PageUp/PageDown, Home/End, or mouse wheel", color: :bright_cyan)

			render(@scroller) do
				paragraph("A focused demo with overflowing content.")
				paragraph("")

				50.times do |index|
					paragraph("Row #{(index + 1).to_s.rjust(2, '0')} - Scroll me")
				end
			end

			paragraph(
				"scroll=#{@scroller.scroll_position} viewport=#{@scroller.viewport_height} content=#{@scroller.content_height} max=#{@scroller.max_scroll}",
				color: :bright_black
			)
			paragraph("Ctrl+C exits", color: :bright_black)
		end
	end
end

class DemoTUIApp < Phlex::TUI::App
	def initialize(...)
		super
		@showcase = ScrollerShowcase.new
	end

	def view_template
		render(@showcase)
	end
end

DemoTUIApp.new.start(fps: nil)
