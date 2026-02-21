#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"

class Demo < Phlex::TUI::App
	include Phlex::Tux

	def view_template
		vstack(gap: 1, padding: [2, 4]) do
			BlockText(
				text: "“Hello, this is some block text written in Departure Mono.”",
				font: Phlex::TUI::Fonts::DepartureMono,
				line_height: 1,
				text_align: :left,
				text_wrap: :pretty,
				hanging_punctuation: true,
			)
		end
	end
end

Demo.new.start(fps: 120)
