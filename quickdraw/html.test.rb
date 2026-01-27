# frozen_string_literal: true

class HTMLTest < Quickdraw::Test
	test "content type" do
		component = Class.new(Phlex::HTML)

		assert_equal component.new.content_type, "text/html"
	end
end
