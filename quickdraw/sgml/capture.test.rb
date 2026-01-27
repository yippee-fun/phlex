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
end
