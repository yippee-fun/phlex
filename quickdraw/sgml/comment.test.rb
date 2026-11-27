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

	test "yields the component outside a selected fragment" do
		component = Class.new(Phlex::HTML) do
			def view_template
				comment { |c| c.fragment("a") { c.span } }
			end
		end

		assert_equal component.new.call(fragments: ["a"]), "<span></span>"
	end
end
