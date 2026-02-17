# frozen_string_literal: true

class TUIFocusTest < Quickdraw::Test
	Context = Struct.new(:runtime)

	class FocusChild < Phlex::TUI
		def initialize(label)
			@label = label
		end

		def view_template
			box(focusable: true, name: :field, border: :rounded) do
				paragraph("#{@label}: #{focused?(:field) ? 'focused' : 'idle'}")
			end
		end
	end

	class FocusRoot < Phlex::TUI
		def initialize
			@left = FocusChild.new("left")
			@right = FocusChild.new("right")
		end

		attr_reader :left
		attr_reader :right

		def view_template
			hstack do
				render(@left)
				render(@right)
			end
		end
	end

	test "focus names are local to owning components" do
		runtime = Phlex::TUI::Runtime.new
		context = Context.new(runtime)
		root = FocusRoot.new

		runtime.begin_frame!
		root.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!

		runtime.focus_next!
		assert_equal [root.left.object_id, :field], runtime.focused_id

		runtime.focus_next!
		assert_equal [root.right.object_id, :field], runtime.focused_id
	end

	test "focusable box requires a name" do
		component = Class.new(Phlex::TUI) do
			def view_template
				box(focusable: true) { "+" }
			end
		end.new

		error = assert_raises(ArgumentError) { component.call }
		assert_equal "focusable boxes require a name", error.message
	end

	test "arrow keys move focus forward and backward" do
		app = Phlex::TUI::App.new

		runtime = app.runtime
		runtime.begin_frame!
		runtime.register_element(id: [:component, :first], owner: self, focusable: true)
		runtime.register_element(id: [:component, :second], owner: self, focusable: true)
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[C")
		assert_equal [:component, :first], runtime.focused_id

		app.__send__(:handle_input, "\e[B")
		assert_equal [:component, :second], runtime.focused_id

		app.__send__(:handle_input, "\e[D")
		assert_equal [:component, :first], runtime.focused_id

		app.__send__(:handle_input, "\e[A")
		assert_equal [:component, :second], runtime.focused_id
	end
end
