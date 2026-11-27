# frozen_string_literal: true

class ContentYieldingTest < Quickdraw::Test
	class TestClass < Phlex::HTML
		def view_template
			select(name: "test") do
				[].each { |i| option_tag(i, i) }
			end

			input(type: "text", name: "other")
		end
	end

	test "an element block that returns an empty enumerable renders nothing" do
		assert_equal TestClass.call, %q(<select name="test"></select><input type="text" name="other">)
	end

	class OtherTestClass < Phlex::HTML
		def view_template
			ul do
				[].each { |i| li { i } }
			end

			p { "hi there" }
		end
	end

	test "an element block that outputs nothing renders an empty element" do
		assert_equal OtherTestClass.call, %q(<ul></ul><p>hi there</p>)
	end

	test "a block's return value is output when it outputs nothing" do
		output = Phlex.html do
			div { :sym_bol }
			div { "<b>" }
			div { safe("<b>") }
			div { 1 }
			div { 1.5 }
			div { nil }
			div { Object.new }
		end

		assert_equal output, %(<div>sym_bol</div><div>&lt;b&gt;</div><div><b></div><div>1</div><div>1.5</div><div></div><div></div>)
	end

	class YieldsArguments < Phlex::HTML
		def view_template
			div { yield(self, 2) }
		end
	end

	test "content blocks given arguments output their return value only when they output nothing" do
		assert_equal YieldsArguments.call { |_, b| b + 1 }, "<div>3</div>"
		assert_equal(YieldsArguments.call { |c, b| c.span { b }; b }, "<div><span>2</span></div>")
	end
end
