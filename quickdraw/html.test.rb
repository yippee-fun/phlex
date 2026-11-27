# frozen_string_literal: true

class HTMLTest < Quickdraw::Test
	test "content type" do
		component = Class.new(Phlex::HTML)

		assert_equal component.new.content_type, "text/html"
	end

	test "Phlex.html copies the caller's instance variables, but not over the component's own" do
		@title = "x"
		@_state = :not_a_state

		assert_equal Phlex.html { span { @title } }, "<span>x</span>"
	end
end
