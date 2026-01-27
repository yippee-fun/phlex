# frozen_string_literal: true

require "sgml_helper"

class WhitespaceTest < Quickdraw::Test
	include SGMLHelper

	test "whitespae between" do
		output = phlex do
			div
			whitespace
			div
		end

		assert_equal output, %(<div></div> <div></div>)
	end

	test "whitespae around" do
		output = phlex do
			div
			whitespace { div }
			div
		end

		assert_equal output, %(<div></div> <div></div> <div></div>)
	end
end
