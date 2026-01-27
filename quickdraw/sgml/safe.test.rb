# frozen_string_literal: true

require "sgml_helper"

class SafeTest < Quickdraw::Test
	include SGMLHelper

	test "safe attribute values" do
		output = phlex do
			a(
				onclick: safe("window.history.back()"),
				href: safe("javascript:window.history.back()"),
			)
		end

		assert_equal output, %(<a onclick="window.history.back()" href="javascript:window.history.back()"></a>)
	end

	test "element content blocks that return safe values" do
		output = phlex do
			script {
				safe(%(console.log("Hello World");))
			}
		end

		assert_equal output, %(<script>console.log("Hello World");</script>)
	end

	test "with invalid input" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { script { safe(123) } }
		end

		assert_equal error.message, "Expected a String."
	end
end
