# frozen_string_literal: true

class CaptureTest < Quickdraw::Test
	class ExampleCaptureWithArguments < Phlex::HTML
		def view_template(&block)
			h1 { capture("a", "b", "c", &block) }
		end
	end

	test "arguments are passed to the capture block" do
		output = ExampleCaptureWithArguments.new.call do |a, b, c|
			"#{a} #{b} #{c}"
		end

		assert_equal output, "<h1>a b c</h1>"
	end

	test "returns an empty string without a block" do
		assert_equal Phlex.html { plain capture.inspect }, %(&quot;&quot;)
	end

	test "yields the component without arguments" do
		component = Class.new(Phlex::HTML) do
			def view_template
				div { capture { |c| c.span(class: "x") } }
			end
		end

		assert_equal component.call, "<div>&lt;span class=&quot;x&quot;&gt;&lt;/span&gt;</div>"
	end

	test "yields a single argument" do
		component = Class.new(Phlex::HTML) do
			def view_template
				div { capture(:a) { |value| "#{value}!" } }
			end
		end

		assert_equal component.call, "<div>a!</div>"
	end

	test "doesn't output what the block returns once it has output something" do
		component = Class.new(Phlex::HTML) do
			def view_template
				div { capture(:a) { |value| span { value }; "returned" } }
			end
		end

		assert_equal component.call, "<div>&lt;span&gt;a&lt;/span&gt;</div>"
	end

	test "vanish runs the block and outputs nothing" do
		ran = false

		component = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				div { vanish { ran = true; span } }
			end
		end

		assert_equal component.call, "<div></div>"
		assert ran
	end
end
