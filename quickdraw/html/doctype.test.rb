# frozen_string_literal: true

class DoctypeTest < Quickdraw::Test
	class Example < Phlex::HTML
		def view_template
			html {
				head {
					doctype
				}
			}
		end
	end

	test do
		assert_equal Example.call, "<html><head><!doctype html></head></html>"
	end
end
