# frozen_string_literal: true

class CallbacksTest < Quickdraw::Test
	class Example < Phlex::HTML
		def before_template
			i { "1" }
		end

		def around_template
			i { "2" }

			super do
				i { "3" }
				yield
				i { "5" }
			end

			i { "6" }
		end

		def after_template
			i { "7" }
		end

		def view_template
			i { "4" }
		end
	end

	test "callbacks are called in the correct order" do
		assert_equal Example.call, "<i>1</i><i>2</i><i>3</i><i>4</i><i>5</i><i>6</i><i>7</i>"
	end

	test "default before_template and after_template accept a block" do
		klass = Class.new(Phlex::HTML) { def view_template = span { "hello" } }
		assert_equal klass.call { "ignored" }, "<span>hello</span>"
	end

	test "hooks receive the content block given to render or with_content" do
		received = []

		child = Class.new(Phlex::HTML) do
			define_method(:before_template) { |&block| received << block&.call }
			define_method(:after_template) { |&block| received << block&.call }
			define_method(:view_template) { |&block| div(&block) }
		end

		parent = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				render(child.new) { "from render" }
				render child.new do
					"from do"
				end
				render(child.new.with_content { "stored" })
				render(child.new.with_content { "ignored" }) { "render wins" }
				render(child.new)
			end
		end

		assert_equal parent.call, "<div>from render</div><div>from do</div><div>stored</div><div>render wins</div><div></div>"
		assert_equal received, ["from render", "from render", "from do", "from do", "stored", "stored", "render wins", "render wins", nil, nil]
	end

	test "a block given to new isn't a content block" do
		component = Class.new(Phlex::HTML) do
			def view_template(&) = div(&)
		end

		assert_equal component.new { "ignored" }.call, "<div></div>"
		assert_equal component.call { "content" }, "<div>content</div>"
	end

	test "a content block receives what view_template yields" do
		child = Class.new(Phlex::HTML) do
			def view_template = div { yield(1, 2) }
		end

		parent = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				render(child.new) { |a, b| "#{a}+#{b}" }
				render(child.new) { |c| c.class.name }
			end
		end

		assert_equal parent.call, "<div>1+2</div><div>Integer</div>"
	end
end
