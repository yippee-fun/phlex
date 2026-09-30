# frozen_string_literal: true

class CustomElementsTest < Quickdraw::Test
	test "custom elements" do
		view = Class.new(Phlex::HTML) do
			register_element :trix_editor
			register_element :trix_toolbar

			def view_template
				div do
					trix_toolbar
					trix_editor { "Hello" }
				end
			end
		end

		assert_equal view.call,
			"<div><trix-toolbar></trix-toolbar><trix-editor>Hello</trix-editor></div>"
	end
end
