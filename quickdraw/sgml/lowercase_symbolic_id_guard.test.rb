# frozen_string_literal: true

class LowercaseSymbolicIDGuardTest < Quickdraw::Test
	test "non lowercase id" do
		view = Class.new(Phlex::HTML) do
			def view_template
				div(iD: "a")
			end
		end

		assert_raises(Phlex::ArgumentError) { view.call }
	end

	test "non symbolic id" do
		view = Class.new(Phlex::HTML) do
			def view_template
				div("id" => "a")
			end
		end

		assert_raises(Phlex::ArgumentError) { view.call }
	end
end
