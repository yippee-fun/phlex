# frozen_string_literal: true

require "sgml_helper"

class RawTest < Quickdraw::Test
	include SGMLHelper

	test "with an unsafe object" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { raw "<div></div>" }
		end

		assert_equal error.message, "You passed an unsafe object to `raw`."
	end

	test "with a safe object" do
		output = phlex { raw safe %(<div class="hello">&</div>) }
		assert_equal output, %(<div class="hello">&</div>)
	end

	test "with nil" do
		output = phlex { div { raw nil } }
		assert_equal output, "<div></div>"
	end

	test "with empty string" do
		output = phlex { div { raw "" } }
		assert_equal output, "<div></div>"
	end
end
