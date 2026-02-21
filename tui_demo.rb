#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"

class Demo < Phlex::TUI::App
	include Phlex::Tux

	def initialize
		super

		text = <<~TEXT
   Stay hungry, stay foolish, and never stop believing in the power of your dreams.
				TEXT

		@text = Phlex::Tux::BlockText.new(
			font: Phlex::TUI::Fonts::DepartureMono,
			line_height: 1.2,
			text_align: :left,
			text:,
			text_wrap: :pretty
		)

		@spinner = Phlex::Tux::Spinner.new(
			label: "Loading inspiration...",
			interval: 0.07,
			color: :cyan
		)
	end

	def view_template
		vstack(padding: [8, 16]) do
			render @spinner
			separator
			render @text
		end
	end
end

Demo.new.start(fps: 120)
