# frozen_string_literal: true

class SVGTest < Quickdraw::Test
	class Example < Phlex::SVG
		def view_template
			svg do
				path(d: "123")
			end
		end
	end

	test do
		assert_equal Example.call, %(<svg><path d="123"></path></svg>)
	end

	test "content_type" do
		component = Class.new(Phlex::SVG)
		assert_equal component.new.content_type, "image/svg+xml"
	end

	test "cdata with string" do
		component = Class.new(Phlex::SVG) do
			def view_template
				cdata("Hello, <[[test]]> World!")
			end
		end

		assert_equal component.call, %(<![CDATA[Hello, <[[test]]>]]<![CDATA[ World!]]>)
	end

	test "cdata with block" do
		component = Class.new(Phlex::SVG) do
			def view_template
				cdata do
					path(d: "123")
				end
			end
		end

		assert_equal component.call, %(<![CDATA[<path d="123"></path>]]>)
	end
end
