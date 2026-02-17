# frozen_string_literal: true

class TUIRuntimeTest < Quickdraw::Test
	test "focus falls forward when focused element is removed" do
		runtime = Phlex::TUI::Runtime.new

		runtime.begin_frame!
		runtime.register_element(id: :a, owner: self, focusable: true)
		runtime.register_element(id: :b, owner: self, focusable: true)
		runtime.register_element(id: :c, owner: self, focusable: true)
		runtime.finalize_frame!

		runtime.focus_next!
		runtime.focus_next!
		assert_equal :b, runtime.focused_id

		runtime.begin_frame!
		runtime.register_element(id: :a, owner: self, focusable: true)
		runtime.register_element(id: :c, owner: self, focusable: true)
		runtime.finalize_frame!

		assert_equal :c, runtime.focused_id
	end

	test "focus falls backward when focused tail is removed" do
		runtime = Phlex::TUI::Runtime.new

		runtime.begin_frame!
		runtime.register_element(id: :a, owner: self, focusable: true)
		runtime.register_element(id: :b, owner: self, focusable: true)
		runtime.register_element(id: :c, owner: self, focusable: true)
		runtime.finalize_frame!

		runtime.focus_previous!
		assert_equal :c, runtime.focused_id

		runtime.begin_frame!
		runtime.register_element(id: :a, owner: self, focusable: true)
		runtime.register_element(id: :b, owner: self, focusable: true)
		runtime.finalize_frame!

		assert_equal :b, runtime.focused_id
	end

	test "focus clears when no focusables remain" do
		runtime = Phlex::TUI::Runtime.new

		runtime.begin_frame!
		runtime.register_element(id: :a, owner: self, focusable: true)
		runtime.finalize_frame!
		runtime.focus_next!

		runtime.begin_frame!
		runtime.finalize_frame!

		assert_equal nil, runtime.focused_id
	end
end
