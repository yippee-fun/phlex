# frozen_string_literal: true

class TUIDialogFocusTest < Quickdraw::Test
	Context = Struct.new(:runtime)

	class DialogExample < Phlex::TUI
		def initialize(show_dialog: true, dialog: true)
			@show_dialog = show_dialog
			@dialog = dialog
		end

		def hide_dialog!
			@show_dialog = false
		end

		def view_template
			box(focusable: true, name: :root) { "root" }

			if @show_dialog
				popover(anchor: :canvas, top: 1, left: 1, dialog: @dialog, name: :settings) do
					box(focusable: true, name: :dialog_first) { "first" }
					box(focusable: true, name: :dialog_second) { "second" }
				end
			end
		end
	end

	test "dialog popover traps focus in top scope" do
		runtime = Phlex::TUI::Runtime.new
		context = Context.new(runtime)
		component = DialogExample.new

		runtime.begin_frame!
		component.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!

		assert_equal [component.object_id, :dialog, :settings], runtime.active_scope

		runtime.focus_next!
		assert_equal runtime.element_ref(owner: component, name: :dialog_first), runtime.focused_id

		runtime.focus_next!
		assert_equal runtime.element_ref(owner: component, name: :dialog_second), runtime.focused_id
	end

	test "non-dialog popover does not trap focus" do
		runtime = Phlex::TUI::Runtime.new
		context = Context.new(runtime)
		component = DialogExample.new(dialog: false)

		runtime.begin_frame!
		component.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!

		assert_equal :root, runtime.active_scope

		runtime.focus_next!
		assert_equal runtime.element_ref(owner: component, name: :root), runtime.focused_id
	end

	test "focus returns to root scope when dialog closes" do
		runtime = Phlex::TUI::Runtime.new
		context = Context.new(runtime)
		component = DialogExample.new

		runtime.begin_frame!
		component.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!
		runtime.focus_next!
		assert_equal runtime.element_ref(owner: component, name: :dialog_first), runtime.focused_id

		component.hide_dialog!
		runtime.begin_frame!
		component.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!

		assert_equal :root, runtime.active_scope
		assert_equal runtime.element_ref(owner: component, name: :root), runtime.focused_id
	end

	test "dialog popovers require a name" do
		component = Class.new(Phlex::TUI) do
			def view_template
				popover(dialog: true) { "dialog" }
			end
		end.new

		error = assert_raises(ArgumentError) { component.call }
		assert_equal "dialog popovers require a name", error.message
	end
end
