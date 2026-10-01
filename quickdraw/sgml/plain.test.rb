# frozen_string_literal: true

require "sgml_helper"

class PlainTest < Quickdraw::Test
	include SGMLHelper

	test "with string" do
		output = phlex { plain "Hello, World!" }
		assert_equal output, "Hello, World!"
	end

	test "with symbol" do
		output = phlex { plain :hello_world }
		assert_equal output, "hello_world"
	end

	test "with integer" do
		output =	phlex { plain 42 }
		assert_equal output, "42"
	end

	test "with float" do
		output = phlex { plain 3.14 }
		assert_equal output, "3.14"
	end

	test "with nil" do
		output = phlex { plain nil }
		assert_equal output, ""
	end

	test "with invalid arguments" do
		assert_raises(Phlex::ArgumentError) do
			phlex { plain [] }
		end
	end

	test "rejects a block without yielding or outputting the content" do
		output = phlex do
			plain "before"
			begin
				plain("text") { raise "must not yield" }
			rescue Phlex::ArgumentError => error
				plain error.message
			end
		end

		assert_equal output, "beforeplain does not accept a block."
	end

	test "rejects a forwarded block" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { plain "text", &proc {} }
		end

		assert_equal error.message, "plain does not accept a block."
	end

	test "accepts a nil block because no block is given" do
		assert_equal phlex { plain "text", &nil }, "text"
	end
end
