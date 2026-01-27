# frozen_string_literal: true

class InlineTest < Quickdraw::Test
	test "inline html with no param" do
		output = Phlex.html do
			h1 { "Hi" }
		end

		assert_equal output, <<~HTML.strip
   <h1>Hi</h1>
HTML
	end

	def title = "Hello"

	test "inline html with a yield param" do
		@ivar = "Hi"
		h1 = "foo"

		output = Phlex.html do |receiver|
			h1 { h1 }
			h1 { @ivar }
			title { receiver.title }
		end

		assert_equal output, <<~HTML.strip
   <h1>foo</h1><h1>Hi</h1><title>Hello</title>
HTML
	end
end
