# frozen_string_literal: true

class ConditionalRenderingTest < Quickdraw::Test
	class Example < Phlex::HTML
		def initialize(render:)
			@render = render
		end

		def render? = @render

		def view_template
			h1 { "Hello" }
		end
	end

	test do
		assert_equal Example.new(render: true).call, "<h1>Hello</h1>"
		assert_equal Example.new(render: false).call, ""
	end

	class ExampleWithContext < Phlex::HTML
		def render? = context[:render]

		def view_template
			h1 { "Hello" }
		end
	end

	test do
		assert_equal ExampleWithContext.new.call(context: { render: true }), "<h1>Hello</h1>"
		assert_equal ExampleWithContext.new.call(context: { render: false }), ""
	end
end
