# frozen_string_literal: true

require "unicode/display_width"

module Phlex::TUI::TextWidth
	module_function

	def each_grapheme(text)
		return enum_for(__method__, text) unless block_given?

		if text.respond_to?(:each_grapheme_cluster)
			text.each_grapheme_cluster { |grapheme| yield grapheme }
		else
			text.scan(/\X/).each { |grapheme| yield grapheme }
		end
	end

	def grapheme_width(grapheme)
		width = Unicode::DisplayWidth.of(grapheme)
		width = 1 if width < 1
		width = 2 if width > 2
		width
	end

	def string_width(text)
		total = 0
		each_grapheme(text) { |grapheme| total += grapheme_width(grapheme) }
		total
	end

	def take_by_width(text, max_width)
		return "" if max_width <= 0

		result = +""
		remaining = max_width

		each_grapheme(text) do |grapheme|
			width = grapheme_width(grapheme)
			break if width > remaining

			result << grapheme
			remaining -= width
		end

		result
	end
end
