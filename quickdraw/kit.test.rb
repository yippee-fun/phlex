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

	class Components::Title < Phlex::HTML
		def view_template
			h1 { "Hello, world" }
		end

		def render?
			false
		end
	end

	class Components::Subtitle < Phlex::HTML
		def view_template
			h2 { "Welcome" }
		end
	end

	class Page < Phlex::HTML
		include Components

		def view_template
			Components::Title()

			Components::Subtitle()
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

	# Github issue: https://github.com/yippee-fun/phlex/issues/979
	test "phlex rendering context" do
		assert_equal Page.call, %(<h2>Welcome</h2>)
	end
end
