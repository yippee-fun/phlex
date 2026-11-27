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

		error = assert_raises(Phlex::DoubleRenderError) { instance.call }
		assert_equal error.message, "You can't render a #{component.name} more than once. To render a component more than once, pass `rerenderable: true` to `call` each time you render it."
	end

	test "can render a component again after rendering it with rerenderable: true" do
		component = Class.new(Phlex::HTML) do
			def initialize
				@count = 0
			end

			def view_template
				@count += 1
				div { @count }
			end
		end

		instance = component.new

		assert_equal instance.call(rerenderable: true), "<div>1</div>"
		assert_equal instance.rendering?, false
		assert_equal instance.call(rerenderable: true), "<div>2</div>"
		assert_equal instance.call, "<div>3</div>"
		assert_raises(Phlex::DoubleRenderError) { instance.call }
	end

	test "rerenderable: true resets after a render that raised" do
		component = Class.new(Phlex::HTML) do
			attr_writer :fail

			def view_template
				raise "boom" if @fail
				div
			end
		end

		instance = component.new
		instance.fail = true

		assert_raises(RuntimeError) { instance.call(rerenderable: true) }

		instance.fail = false

		assert_equal instance.call, "<div></div>"
	end

	test "rerenderable: true doesn't allow rendering a component that was already rendered" do
		instance = Class.new(Phlex::HTML).new
		instance.call

		assert_raises(Phlex::DoubleRenderError) { instance.call(rerenderable: true) }
		assert_raises(Phlex::DoubleRenderError) { instance.call(rerenderable: true) }
	end

	test "rerenderable: true doesn't allow rendering a component from inside its own render" do
		component = Class.new(Phlex::HTML) do
			def view_template
				call(rerenderable: true)
			end
		end

		instance = component.new

		assert_raises(Phlex::DoubleRenderError) { instance.call(rerenderable: true) }
	end

	test "rerenderable: true renders fragments" do
		component = Class.new(Phlex::HTML) do
			def view_template
				fragment(:a) { h1 { "a" } }
				fragment(:b) { h2 { "b" } }
			end
		end

		instance = component.new

		assert_equal instance.call(fragments: [:a], rerenderable: true), "<h1>a</h1>"
		assert_equal instance.call(fragments: [:b], rerenderable: true), "<h2>b</h2>"
	end

	test "can't render a class that isn't a component" do
		error = assert_raises(Phlex::ArgumentError) do
			Phlex.html { render String }
		end

		assert_equal error.message, "You can't render a String."
	end

	test "can't render Phlex::SGML itself" do
		error = assert_raises(Phlex::ArgumentError) do
			Phlex.html { render Phlex::SGML }
		end

		assert_equal error.message, "You can't render a Phlex::SGML."
	end

	test "renders a string as text" do
		assert_equal Phlex.html { render "<b>" }, "&lt;b&gt;"
	end

	test "renders each item of an enumerable with the block" do
		item = Class.new(Phlex::HTML) do
			def initialize(name) = @name = name

			def view_template(&) = li(id: @name, &)
		end

		output = Phlex.html do
			render([item.new("a"), item.new("b")]) { "x" }
		end

		assert_equal output, %(<li id="a">x</li><li id="b">x</li>)
	end

	test "renders a proc or method with the component unless it takes no arguments" do
		component = Class.new(Phlex::HTML) do
			def view_template
				render -> { span }
				render proc { |c| c.em(class: "x") }
				render method(:strong_tag)
				render method(:bold)
			end

			def strong_tag = strong

			def bold(c) = c.b
		end

		assert_equal component.call, %(<span></span><em class="x"></em><strong></strong><b></b>)
	end

	test "renders nothing for nil without a block" do
		assert_equal Phlex.html { render nil }, ""
		assert_equal Phlex.html { render(nil) { "x" } }, "x"
	end

	test "doesn't render when render? is false" do
		component = Class.new(Phlex::HTML) do
			def view_template = span

			private def render? = false
		end

		instance = component.new

		assert_equal instance.internal_call(state: Phlex::SGML::State.new(user_context: {}, output_buffer: +"", fragments: nil)), ""
		assert_equal component.call, ""
	end

	test "the component being rendered is reset once a render ends" do
		require "components"

		inner = Class.new(Phlex::HTML) do
			def view_template = span
		end

		outer = Class.new(Phlex::HTML) do
			define_method(:view_template) { render inner.new }
		end

		outer.call

		error = assert_raises(RuntimeError) { Components::SayHi("Joel") }
		assert_equal error.message, "You can't call `SayHi' outside of a Phlex rendering context."
	end
end
