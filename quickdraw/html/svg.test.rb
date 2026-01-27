# frozen_string_literal: true

class HTMLSVGTest < Quickdraw::Test
	class Example < Phlex::HTML
		def view_template
			svg do |s|
				s.path(d: "321")
			end
		end
	end

	class ExampleWithoutContent < Phlex::HTML
		def view_template
			svg
		end
	end

	test "rendering SVG without content" do
		assert_equal %(<svg></svg>), ExampleWithoutContent.call
	end

	test "rendering SVG inside HTML components" do
		assert_equal %(<svg><path d="321"></path></svg>), Example.call
	end
end
