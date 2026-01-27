# frozen_string_literal: true

class KitTest < Quickdraw::Test
	require "components"
	require "sgml_helper"
	include SGMLHelper

	class Example < Phlex::HTML
		include Components

		def view_template
			SayHi("Joel", times: 2) { "Inside" }
			Components::SayHi("Will", times: 1) { "Inside" }
		end
	end

	test "raises when you try to render a component outside of a rendering context" do
		error = assert_raises(RuntimeError) { Components::SayHi("Joel") }
		assert_equal error.message, "You can't call `SayHi' outside of a Phlex rendering context."
	end

	test "defines methods for its components" do
		assert_equal Example.new.call, %(<article><h1>Hi Joel</h1><h1>Hi Joel</h1>Inside</article><article><h1>Hi Will</h1>Inside</article>)
	end

	test "nested kits" do
		assert_equal phlex { Components::Foo::Bar() }, "<h1>Bar</h1>"
	end
end
