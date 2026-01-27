# frozen_string_literal: true

require "sgml_helper"

class CommentTest < Quickdraw::Test
	include SGMLHelper

	test "text comment" do
		output = phlex do
			comment { "Hello World" }
		end

		assert_equal output, "<!-- Hello World -->"
	end

	test "block comment with markup" do
		output = phlex do
			comment do
				h1 { "Hello World" }
			end
		end

		assert_equal output, "<!-- <h1>Hello World</h1> -->"
	end
end
