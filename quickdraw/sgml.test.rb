# frozen_string_literal: true

class SGMLTest < Quickdraw::Test
	test "components render with a default blank view_template" do
		component = Class.new(Phlex::HTML) do
			def view_template
			end
		end

		assert_equal component.new.call, ""
	end

	test "components with old `template` method render warning" do
		component = Class.new(Phlex::HTML) do
			def template
				span "old template"
			end
		end

		assert_equal component.new.call, Phlex::Escape.html_escape(
			%(Phlex Warning: Your `#{component.name}` class doesn't define a `view_template` method. If you are upgrading to Phlex 2.x make sure to rename your `template` method to `view_template`. See: https://beta.phlex.fun/guides/v2-upgrade.html)
		)
	end

	test "components with no `view_template` method render warning" do
		component = Class.new(Phlex::HTML)

		assert_equal component.new.call, Phlex::Escape.html_escape(
			%(Phlex Warning: Your `#{component.name}` class doesn't define a `view_template` method. If you are upgrading to Phlex 2.x make sure to rename your `template` method to `view_template`. See: https://beta.phlex.fun/guides/v2-upgrade.html)
		)
	end

	test "can't render a component more than once" do
		component = Class.new(Phlex::HTML)

		instance = component.new
		instance.call

		assert_raises(Phlex::DoubleRenderError) { instance.call }
	end
end
