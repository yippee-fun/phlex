#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"

class Demo < Phlex::TUI::App
	include Phlex::Tux

	def view_template
		vstack(gap: 1, padding: [4, 8]) do
			text = <<~TEXT
				The only way to do great work is to love what you do. If you haven’t found it yet, keep looking. Don’t settle. As with all matters of the heart, you’ll know when you find it. Stay hungry, stay foolish, and never stop believing in the power of your dreams.
			TEXT

			BlockText(
				font: Phlex::TUI::Fonts::DepartureMono,
				line_height: 1.2,
				text_align: :left,
				text:,
				text_wrap: :pretty,
			)
		end
	end
end

Demo.new.start(fps: 120)
