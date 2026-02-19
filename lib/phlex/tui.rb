# frozen_string_literal: true

class Phlex::TUI
	def view_template
	end

	def call(tree = Phlex::TUI::Tree.new, context: nil, &)
		@tree = tree
		@context = context unless context.nil?
		previous_phlex_tui_component = Thread.current[:__phlex_tui_component__]
		Thread.current[:__phlex_tui_component__] = self

		yield_content { view_template(&) }
		tree
	ensure
		Thread.current[:__phlex_tui_component__] = previous_phlex_tui_component
	end

	def app
		@context
	end

	def request_render!
		app&.request_render!
		nil
	end

	def runtime
		@context&.runtime
	end

	def hstack(*, **, &)
		box(*, **, direction: :horizontal, &)
	end

	def vstack(*, **, &)
		box(*, **, direction: :vertical, &)
	end

	def separator
		box(height: :grow, width: :grow)
	end

	def hr(border:, width: :grow, padding: 0)
		box(padding:, width:) do
			box(border: { top: border }, width: :grow)
		end
	end

	def vr(border:, height: :grow, padding: 0)
		box(padding:, height:) do
			box(border: { left: border }, height: :grow)
		end
	end

	def box(*, focusable: false, name: nil, pointer_events: :auto, overflow: :none, on_focus: nil, on_blur: nil, on_key_down: nil, on_key_up: nil, on_mouse_down: nil, on_mouse_up: nil, on_mouse_move: nil, on_mouse_wheel: nil, on_mouse_enter: nil, on_mouse_leave: nil, **)
		handlers = {
			focus: on_focus,
			blur: on_blur,
			key_down: on_key_down,
			key_up: on_key_up,
			mouse_down: on_mouse_down,
			mouse_up: on_mouse_up,
			mouse_move: on_mouse_move,
			mouse_wheel: on_mouse_wheel,
			mouse_enter: on_mouse_enter,
			mouse_leave: on_mouse_leave,
		}.compact

		if !handlers.empty? && name.nil?
			raise ArgumentError, "boxes with event handlers require a name"
		end

		requires_focus = !on_focus.nil? || !on_blur.nil? || !on_key_down.nil? || !on_key_up.nil?
		if requires_focus && !focusable
			raise ArgumentError, "boxes with event handlers must be focusable"
		end

		if focusable && name.nil?
			raise ArgumentError, "focusable boxes require a name"
		end

		node = Phlex::TUI::Box.new(*, parent: @tree.current_parent, owner: self, focusable:, name:, pointer_events:, overflow:, **)
		@tree.attach(node)
		@tree.stack << node

		begin
			if runtime && (focusable || !handlers.empty?)
				element_id = focus_key(name)
				runtime.register_element(id: element_id, owner: self, handlers:, focusable:, scope: focus_scope_for(node))
				runtime.update_element_node(element_id, node)
			end

			yield_content { yield } if block_given?
			node
		ensure
			@tree.stack.pop
		end
	end

	def focused?(name)
		return false unless runtime

		runtime.focused?(focus_key(name))
	end

	def render(component, &)
		case component
		in Phlex::TUI
			component.call(@tree, context: @context, &)
		end
	end

	def popover(*, dialog: false, name: nil, **)
		if dialog && name.nil?
			raise ArgumentError, "dialog popovers require a name"
		end

		node = Phlex::TUI::Popover.new(*, parent: @tree.current_parent, owner: self, dialog:, name:, **)
		@tree.attach(node)

		if dialog && runtime
			runtime.register_dialog_scope(scope: node.dialog_scope_key, z: node.z)
		end

		@tree.stack << node

		begin
			yield_content { yield } if block_given?
			node
		ensure
			@tree.stack.pop
		end
	end

	def table(...)
		container(Phlex::TUI::Table, ...)
	end

	def row(...)
		container(Phlex::TUI::Row, ...)
	end

	def col(...)
		container(Phlex::TUI::Col, ...)
	end

	def paragraph(value = nil, **options)
		span_options = options
		paragraph_options = options.dup
		paragraph_options.delete(:font)

		node = Phlex::TUI::Paragraph.new(parent: @tree.current_parent, **paragraph_options)
		@tree.attach(node)
		@tree.stack << node
		span(value, **span_options) unless value.nil?
		yield_content { yield } if block_given?
		nil
	ensure
		@tree.stack.pop
	end

	def span(value = nil, **)
		node = Phlex::TUI::Span.new(content: value, parent: @tree.current_parent, **)
		@tree.attach(node)
		nil
	end

	def embed(*, **, &)
		node = Phlex::TUI::Embed.new(*, parent: @tree.current_parent, **, &)
		@tree.attach(node)
		nil
	end

	private def yield_content
		return unless block_given?

		parent = @tree.current_parent
		original_length = parent.children.length
		content = yield

		implicit_output(content) if parent.children.length == original_length
	end

	private def focus_key(name)
		[object_id, name]
	end

	private def focus_scope_for(node)
		current = node

		while current
			if Phlex::TUI::Popover === current && current.dialog?
				return current.dialog_scope_key
			end

			current = current.parent
		end

		:root
	end

	private def implicit_output(content)
		case content
		when String
			if Phlex::TUI::Paragraph === @tree.current_parent
				span(content)
			else
				paragraph(content)
			end
		when Symbol, Numeric
			if Phlex::TUI::Paragraph === @tree.current_parent
				span(content.to_s)
			else
				paragraph(content.to_s)
			end
		end
	end

	private def container(klass, *, **)
		node = klass.new(*, parent: @tree.current_parent, **)
		@tree.attach(node)
		@tree.stack << node
		yield_content { yield } if block_given?
		nil
	ensure
		@tree.stack.pop
	end
end
