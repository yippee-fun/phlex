# frozen_string_literal: true

class TUIEventsTest < Quickdraw::Test
	Context = Struct.new(:runtime)

	class EventOwner
		def initialize
			@key_down_events = []
			@text_input_events = []
			@focus_events = []
			@blur_events = []
			@mouse_events = []
			@hover_events = []
			@bubble_events = []
		end

		attr_reader :key_down_events
		attr_reader :text_input_events
		attr_reader :focus_events
		attr_reader :blur_events
		attr_reader :mouse_events
		attr_reader :hover_events
		attr_reader :bubble_events
	end

	Node = Struct.new(:row, :col, :width, :height, :pointer_events)

	test "non-navigation keys dispatch on_key_down to focused element" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner:,
			handlers: {
				key_down: -> (event) { @key_down_events << event.key },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "a")

		assert_equal [:a], owner.key_down_events
	end

	test "printable keys dispatch text_input to focused element" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner:,
			handlers: {
				text_input: -> (event) { @text_input_events << event.text },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "a")

		assert_equal ["a"], owner.text_input_events
	end

	test "bracketed paste dispatches one text_input event" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner:,
			handlers: {
				text_input: -> (event) { @text_input_events << event.text },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "\e[200~")
		app.__send__(:handle_input, "h")
		app.__send__(:handle_input, "i")
		app.__send__(:handle_input, "\n")
		app.__send__(:handle_input, "x")
		app.__send__(:handle_input, "\e[201~")

		assert_equal ["hi\nx"], owner.text_input_events
	end

	test "navigation keys dispatch on_key_down and move focus by default" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :first],
			owner:,
			handlers: {
				key_down: -> (event) { @key_down_events << event.key },
			},
			focusable: true,
			scope: :root
		)
		runtime.register_element(
			id: [:owner, :second],
			owner:,
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "\e[C")

		assert_equal [:right], owner.key_down_events
		assert_equal [:owner, :second], runtime.focused_id
	end

	test "navigation keys can be prevented by key_down handler" do
		app = Phlex::TUI::App.new
		first_owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :first],
			owner: first_owner,
			handlers: {
				key_down: -> (event) do
					@key_down_events << event.key
					event.prevent_default! if event.key?(:right)
				end,
			},
			focusable: true,
			scope: :root
		)
		runtime.register_element(
			id: [:owner, :second],
			owner: self,
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "\e[C")

		assert_equal [:right], first_owner.key_down_events
		assert_equal [:owner, :first], runtime.focused_id
	end

	test "navigation emits blur then focus" do
		app = Phlex::TUI::App.new
		first_owner = EventOwner.new
		second_owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :first],
			owner: first_owner,
			handlers: {
				blur: -> (event) { @blur_events << event.name },
			},
			focusable: true,
			scope: :root
		)
		runtime.register_element(
			id: [:owner, :second],
			owner: second_owner,
			handlers: {
				focus: -> (event) { @focus_events << event.name },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "\e[C")

		assert_equal [:first], first_owner.blur_events
		assert_equal [:second], second_owner.focus_events
	end

	test "boxes with handlers must be focusable and named" do
		unnamed = Class.new(Phlex::TUI) do
			def view_template
				box(focusable: true, on_key_down: -> (_event) {}) { "x" }
			end
		end.new

		error = assert_raises(ArgumentError) { unnamed.call }
		assert_equal "boxes with event handlers require a name", error.message

		not_focusable = Class.new(Phlex::TUI) do
			def view_template
				box(name: :x, on_key_down: -> (_event) {}) { "x" }
			end
		end.new

		error = assert_raises(ArgumentError) { not_focusable.call }
		assert_equal "boxes with event handlers must be focusable", error.message
	end

	test "mouse down dispatches to hit-tested target" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :mouse_target],
			owner:,
			handlers: {
				mouse_down: -> (event) { @mouse_events << [event.class, event.col, event.row] },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :mouse_target], Node.new(1, 1, 4, 2, :auto))
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;2;2M")

		assert_equal [[Phlex::TUI::MouseDownEvent, 1, 1]], owner.mouse_events
	end

	test "mouse up dispatches to captured target when released outside" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :mouse_target],
			owner:,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :down },
				mouse_up: -> (_event) { @mouse_events << :up },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :mouse_target], Node.new(1, 1, 4, 2, :auto))
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;2;2M")
		app.__send__(:handle_input, "\e[<0;30;20m")

		assert_equal [:down, :up], owner.mouse_events
	end

	test "hit testing uses final node geometry at frame finalize" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		node = Node.new(0, 0, 2, 1, :auto)

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :moving_target],
			owner:,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :hit },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :moving_target], node)

		node.col = 5
		node.row = 3
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;6;4M")

		assert_equal [:hit], owner.mouse_events
	end

	test "active dialog scope blocks root mouse events" do
		app = Phlex::TUI::App.new
		root_owner = EventOwner.new
		dialog_owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:root, :target],
			owner: root_owner,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :root },
			},
			scope: :root
		)
		runtime.update_element_node([:root, :target], Node.new(0, 0, 10, 4, :auto))

		dialog_scope = [:owner, :dialog, :settings]
		runtime.register_dialog_scope(scope: dialog_scope, z: 1)
		runtime.register_element(
			id: [:dialog, :target],
			owner: dialog_owner,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :dialog },
			},
			scope: dialog_scope
		)
		runtime.update_element_node([:dialog, :target], Node.new(5, 5, 2, 2, :auto))
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;1;1M")

		assert_equal [], root_owner.mouse_events
		assert_equal [], dialog_owner.mouse_events
	end

	test "pointer_events none allows hit to pass through" do
		app = Phlex::TUI::App.new
		back = EventOwner.new
		top = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:back, :target],
			owner: back,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :back },
			},
			scope: :root
		)
		runtime.update_element_node([:back, :target], Node.new(0, 0, 5, 2, :auto))

		runtime.register_element(
			id: [:top, :cover],
			owner: top,
			handlers: {
				mouse_down: -> (_event) { @mouse_events << :top },
			},
			scope: :root
		)
		runtime.update_element_node([:top, :cover], Node.new(0, 0, 5, 2, :none))
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;1;1M")

		assert_equal [:back], back.mouse_events
		assert_equal [], top.mouse_events
	end

	test "mouse move dispatches enter and leave hover events" do
		app = Phlex::TUI::App.new
		left = EventOwner.new
		right = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:left, :target],
			owner: left,
			handlers: {
				mouse_enter: -> (_event) { @hover_events << :enter },
				mouse_leave: -> (_event) { @hover_events << :leave },
			},
			scope: :root
		)
		runtime.update_element_node([:left, :target], Node.new(0, 0, 2, 1, :auto))

		runtime.register_element(
			id: [:right, :target],
			owner: right,
			handlers: {
				mouse_enter: -> (_event) { @hover_events << :enter },
				mouse_leave: -> (_event) { @hover_events << :leave },
			},
			scope: :root
		)
		runtime.update_element_node([:right, :target], Node.new(0, 2, 2, 1, :auto))
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<32;1;1M")
		app.__send__(:handle_input, "\e[<32;3;1M")

		assert_equal [:enter, :leave], left.hover_events
		assert_equal [:enter], right.hover_events
	end

	test "key_down bubbles from child to parent" do
		app = Phlex::TUI::App.new
		child_owner = EventOwner.new
		parent_owner = EventOwner.new
		runtime = app.runtime

		parent_node = Node.new(0, 0, 6, 3, :auto)
		child_node = Node.new(1, 1, 2, 1, :auto)
		child_node.define_singleton_method(:parent) { parent_node }

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :parent],
			owner: parent_owner,
			handlers: {
				key_down: -> (event) { @bubble_events << [event.current_name, event.target_name, event.key] },
			},
			focusable: true,
			scope: :root
		)
		runtime.update_element_node([:owner, :parent], parent_node)

		runtime.register_element(
			id: [:owner, :child],
			owner: child_owner,
			handlers: {
				key_down: -> (event) { @bubble_events << [event.current_name, event.target_name, event.key] },
			},
			focusable: true,
			scope: :root
		)
		runtime.update_element_node([:owner, :child], child_node)
		runtime.finalize_frame!

		runtime.focus_next!
		runtime.focus_next!
		app.__send__(:handle_input, "x")

		assert_equal [[:child, :child, :x]], child_owner.bubble_events
		assert_equal [[:parent, :child, :x]], parent_owner.bubble_events
	end

	test "mouse_down bubbles from child to parent" do
		app = Phlex::TUI::App.new
		child_owner = EventOwner.new
		parent_owner = EventOwner.new
		runtime = app.runtime

		parent_node = Node.new(0, 0, 6, 3, :auto)
		child_node = Node.new(1, 1, 2, 1, :auto)
		child_node.define_singleton_method(:parent) { parent_node }

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :parent],
			owner: parent_owner,
			handlers: {
				mouse_down: -> (event) { @bubble_events << [event.current_name, event.target_name] },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :parent], parent_node)

		runtime.register_element(
			id: [:owner, :child],
			owner: child_owner,
			handlers: {
				mouse_down: -> (event) { @bubble_events << [event.current_name, event.target_name] },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :child], child_node)
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;2;2M")

		assert_equal [[:child, :child]], child_owner.bubble_events
		assert_equal [[:parent, :child]], parent_owner.bubble_events
	end

	test "stop_propagation halts bubbling at current target" do
		app = Phlex::TUI::App.new
		child_owner = EventOwner.new
		parent_owner = EventOwner.new
		runtime = app.runtime

		parent_node = Node.new(0, 0, 6, 3, :auto)
		child_node = Node.new(1, 1, 2, 1, :auto)
		child_node.define_singleton_method(:parent) { parent_node }

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :parent],
			owner: parent_owner,
			handlers: {
				mouse_down: -> (_event) { @bubble_events << :parent },
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :parent], parent_node)

		runtime.register_element(
			id: [:owner, :child],
			owner: child_owner,
			handlers: {
				mouse_down: -> (event) do
					@bubble_events << :child
					event.stop_propagation!
				end,
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :child], child_node)
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<0;2;2M")

		assert_equal [:child], child_owner.bubble_events
		assert_equal [], parent_owner.bubble_events
	end

	test "mouse enter and leave dispatch inner to outer order" do
		app = Phlex::TUI::App.new
		child_owner = EventOwner.new
		parent_owner = EventOwner.new
		order = []
		runtime = app.runtime

		parent_node = Node.new(0, 0, 6, 3, :auto)
		child_node = Node.new(1, 1, 2, 1, :auto)
		child_node.define_singleton_method(:parent) { parent_node }

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :parent],
			owner: parent_owner,
			handlers: {
				mouse_enter: -> (_event) do
					@hover_events << :enter_parent
					order << :enter_parent
				end,
				mouse_leave: -> (_event) do
					@hover_events << :leave_parent
					order << :leave_parent
				end,
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :parent], parent_node)

		runtime.register_element(
			id: [:owner, :child],
			owner: child_owner,
			handlers: {
				mouse_enter: -> (_event) do
					@hover_events << :enter_child
					order << :enter_child
				end,
				mouse_leave: -> (_event) do
					@hover_events << :leave_child
					order << :leave_child
				end,
			},
			scope: :root
		)
		runtime.update_element_node([:owner, :child], child_node)
		runtime.finalize_frame!

		app.__send__(:handle_input, "\e[<32;2;2M")
		app.__send__(:handle_input, "\e[<32;1;1M")
		app.__send__(:handle_input, "\e[<32;10;10M")

		assert_equal [:enter_child, :enter_parent, :leave_child, :leave_parent], order
		assert_equal [:enter_child, :leave_child], child_owner.hover_events
		assert_equal [:enter_parent, :leave_parent], parent_owner.hover_events
	end

	test "symbol handler dispatches owner method" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		owner.define_singleton_method(:record_key_down) do |event|
			@key_down_events << event.key
		end

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner:,
			handlers: {
				key_down: :record_key_down,
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		app.__send__(:handle_input, "z")

		assert_equal [:z], owner.key_down_events
	end

	test "dispatch does not request render unless handler does" do
		app = Phlex::TUI::App.new
		owner = EventOwner.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner:,
			handlers: {
				key_down: -> (event) { @key_down_events << event.key },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		assert_equal false, app.__send__(:render_requested?)

		app.__send__(:handle_input, "a")

		assert_equal [:a], owner.key_down_events
		assert_equal false, app.__send__(:render_requested?)
	end

	test "handlers can request render explicitly" do
		app = Phlex::TUI::App.new
		runtime = app.runtime

		runtime.begin_frame!
		runtime.register_element(
			id: [:owner, :field],
			owner: self,
			handlers: {
				key_down: -> (_event) { app.request_render! },
			},
			focusable: true,
			scope: :root
		)
		runtime.finalize_frame!
		runtime.focus_next!

		assert_equal false, app.__send__(:render_requested?)

		app.__send__(:handle_input, "a")

		assert_equal true, app.__send__(:render_requested?)
	end

	test "on_mouse_down maps to mouse_down handler" do
		runtime = Phlex::TUI::Runtime.new
		context = Context.new(runtime)

		component = Class.new(Phlex::TUI) do
			def increment(_event)
			end

			def view_template
				box(focusable: true, name: :plus, on_mouse_down: :increment) { "+" }
			end
		end.new

		runtime.begin_frame!
		component.call(Phlex::TUI::Tree.new, context:)
		runtime.finalize_frame!

		event = runtime.event_for(runtime.element_ref(owner: component, name: :plus))
		assert_equal :increment, event[:handlers][:mouse_down]
	end
end
