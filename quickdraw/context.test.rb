# frozen_string_literal: true

class ContextTest < Quickdraw::Test
	test "user context passed in from the outside" do
		example = Class.new(Phlex::HTML) do
			define_method :view_template do
				h1 { context[:heading] }
			end
		end

		context = { heading: "Hello, World!" }
		assert_equal example.new.call(context:), %(<h1>Hello, World!</h1>)
	end

	test "user context passed down" do
		a = Class.new(Phlex::HTML) do
			define_method :view_template do
				h1 { context[:heading] }
			end
		end

		b = Class.new(Phlex::HTML) do
			define_method :view_template do
				context[:heading] = "Hello, World!"
				render a.new
			end
		end

		assert_equal b.new.call, %(<h1>Hello, World!</h1>)
	end

	test "raises an ArgumentError if you access the context before rendering" do
		component = Phlex::HTML.new

		error = assert_raises(Phlex::ArgumentError) { component.context }

		assert_equal error.message, <<~MESSAGE
			You can’t access the context before the component has started rendering.
		MESSAGE
	end
end
