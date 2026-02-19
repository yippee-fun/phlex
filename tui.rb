#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "phlex"

class InputShowcase < Phlex::TUI
	def initialize
		@single = Phlex::Tux::Input.new(
			value: "hello world",
			placeholder: "Type here...",
			border: :rounded,
			padding: [0, 1],
			height: 3,
			width: :grow,
			on_change: -> (value) { @single_value = value }
		)

		@multiline = Phlex::Tux::Input.new(
			multiline: true,
			placeholder: "Multiline input (paste with Cmd+V)",
			border: :rounded,
			padding: [0, 1],
			height: 6,
			width: :grow,
			on_change: -> (value) { @multiline_value = value }
		)

		@single_value = @single.value
		@multiline_value = @multiline.value

		@selectable = Phlex::Tux::Text.new(
			value: "This is selectable text. Drag to select and press Ctrl+C to copy.\nIt is read-only but still focusable.",
			border: :rounded,
			padding: [0, 1],
			height: 3,
			width: :grow,
		)
	end

	def view_template
		box(width: :grow, height: :grow, border: :rounded, padding: 1, gap: 1) do
			paragraph("Phlex::Tux::Input Demo", bold: true)
			paragraph("Click an input to focus. Arrow/Home/End/Alt+Arrow work.", color: :bright_cyan)
			paragraph("Paste with Cmd+V. Ctrl+V pastes internal clipboard. Ctrl+G copies selection. Ctrl+C exits.", color: :bright_cyan)

			paragraph("Single line", bold: true)
			render(@single)

			paragraph("Multiline", bold: true)
			render(@multiline)

			paragraph("Selectable Text (read-only)", bold: true)
			render(@selectable)

			box(border: :rounded, padding: [0, 1], height: :grow, width: :grow) do
				paragraph("Live values", bold: true)
				paragraph("single=#{@single_value.inspect}", color: :bright_black)
				paragraph("multiline=#{@multiline_value.inspect}", color: :bright_black)
			end
		end
	end
end

class DemoTUIApp < Phlex::TUI::App
	def initialize(...)
		super
		@showcase = InputShowcase.new
	end

	def view_template
		render(@showcase)
	end
end

DemoTUIApp.new.start(fps: nil)
