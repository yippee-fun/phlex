# frozen_string_literal: true

class FlushTest < Quickdraw::Test
	class YieldingComponent < Phlex::HTML
		def view_template
			div { yield self, "hello" }
		end
	end

	[{}, { id: "greeting" }].each do |attributes|
		test "flushing preserves implicit element output with #{attributes.inspect}" do
			output = Phlex.html do
				div(**attributes) { flush; "hello" }
			end

			opening = attributes.empty? ? "<div>" : '<div id="greeting">'
			assert_equal output, "#{opening}hello</div>"
		end
	end

	test "flushing preserves implicit output in helpers" do
		output = Phlex.html do
			comment { flush; "hello" }
			whitespace { flush; "hello" }
			render -> { flush; "hello" }
		end

		assert_equal output, "<!-- hello --> hello hello"
	end

	test "flushing preserves implicit output when yielding arguments" do
		output = YieldingComponent.new.call do |component, greeting|
			component.flush
			greeting
		end

		assert_equal output, "<div>hello</div>"
	end

	test "flushed writes suppress implicit output even when the buffer started empty" do
		output = Phlex.html do
			render -> { plain "hello"; flush; "duplicate" }
		end

		assert_equal output, "hello"
	end

	test "refilling the buffer to its original size suppresses implicit output" do
		output = Phlex.html do
			div { flush; plain "12345"; "duplicate" }
		end

		assert_equal output, "<div>12345</div>"
	end

	test "repeated flushes preserve streaming chunks and implicit output" do
		chunks = []
		Phlex::HTML.new.call(chunks) do |component|
			component.div { component.flush; component.flush; "hello" }
		end

		assert_equal chunks, ["<div>", "", "hello</div>"]
	end
end
