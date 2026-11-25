# frozen_string_literal: true

require "json"

class JSONEscapeTest < Quickdraw::Test
	test "escapes HTML delimiters and JavaScript line separators" do
		input = "<>&\u2028\u2029"
		output = Phlex::HTML.new.json_escape(input)

		assert_equal output, '\u003c\u003e\u0026\u2028\u2029'
		assert_equal input, "<>&\u2028\u2029"
	end

	test "escaping JSON preserves its parsed value and existing escapes" do
		value = { "markup" => "</script><&>", "text" => "\"\\é😀\u2028\u2029" }
		input = JSON.generate(value).freeze
		output = Phlex::HTML.new.json_escape(input)

		assert_equal JSON.parse(output), value
		assert_equal input, JSON.generate(value)
		assert_equal output.match?(/[<>&\u2028\u2029]/), false
	end
end
