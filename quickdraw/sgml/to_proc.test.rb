# frozen_string_literal: true

require "sgml_helper"

class ToProcTest < Quickdraw::Test
	include SGMLHelper

	class Example < Phlex::HTML
		def view_template(&)
			article(&)
		end

		def slot(&)
			render(&)
		end
	end

	class Sub < Phlex::HTML
		def view_template
			h1 { "Sub" }
		end
	end

	test "rendering components via #to_proc" do
		output = phlex do
			render Example do |e|
				e.slot(&Sub.new)
			end
		end

		assert_equal output, %(<article><h1>Sub</h1></article>)
	end
end
