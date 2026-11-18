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

	test "safe attribute values share an attribute cache entry" do
		cache = Phlex::FIFO.new(max_bytesize: 2 ** 20)

		5.times do
			cache.fetch({ class: Phlex::SGML::SafeValue.new("a") }) { +" class=\"a\"" }
		end

		assert_equal cache.size, 1
	end

	# phlex-native serialises attributes without the cache.
	unless defined?(Phlex::Native)
		test "rendering safe attribute values hits the attribute cache" do
			value = "safe-value-cache-#{object_id}"
			2.times { phlex { div(class: safe(value)) } }

			assert_equal Phlex::ATTRIBUTE_CACHE[{ class: Phlex::SGML::SafeValue.new(value) }], %( class="#{value}")
		end
	end

	test "safe values are not equal to strings" do
		refute_equal Phlex::SGML::SafeValue.new("x"), "x"
		refute_equal "x", Phlex::SGML::SafeValue.new("x")
		refute Phlex::SGML::SafeValue.new("x").eql?("x")
		assert_equal Phlex::SGML::SafeValue.new("x"), Phlex::SGML::SafeValue.new("x")
		assert Phlex::SGML::SafeValue.new("x").eql?(Phlex::SGML::SafeValue.new("x"))
		assert_equal Phlex::SGML::SafeValue.new("x").hash, Phlex::SGML::SafeValue.new("x").hash
	end

	test "cached unsafe and safe reference attributes stay distinct" do
		2.times do
			assert_equal phlex { a(href: "javascript:alert(1)") }, %(<a></a>)
			assert_equal phlex { a(href: safe("javascript:alert(1)")) }, %(<a href="javascript:alert(1)"></a>)
		end
	end

	test "with invalid input" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { script { safe(123) } }
		end

		assert_equal error.message, "Expected a String."
	end
end
