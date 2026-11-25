# frozen_string_literal: true

class ParentTest < Quickdraw::Test
	Child = Class.new(Phlex::HTML) do
		attr_reader :seen_parent

		define_method(:view_template) { @seen_parent = parent }
	end

	test "a component rendered from the outside has no parent" do
		child = Child.new
		child.call

		assert_equal child.parent, nil
		assert_equal child.seen_parent, nil
	end

	test "a component rendered by another component has that component as its parent" do
		child = Child.new

		outer = Class.new(Phlex::HTML) do
			define_method(:view_template) { render child }
		end.new

		outer.call

		assert child.parent.equal?(outer)
		assert child.seen_parent.equal?(outer)
	end

	test "the parent is the component that called render, not the one yielding" do
		child = Child.new

		layout = Class.new(Phlex::HTML) do
			define_method(:view_template) { |&block| div(&block) }
		end.new

		page = Class.new(Phlex::HTML) do
			define_method(:view_template) { render(layout) { render child } }
		end.new

		page.call

		assert child.parent.equal?(page)
	end

	test "a component can define its own parent method" do
		example = Class.new(Phlex::HTML) do
			define_method(:parent) { "mine" }
			define_method(:view_template) { plain parent }
		end

		assert_equal example.new.call, "mine"
	end
end
