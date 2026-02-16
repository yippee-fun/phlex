# frozen_string_literal: true

class Phlex::TUI
	def view_template
	end

	def call(tree = Phlex::TUI::Tree.new, &)
		@tree = tree
		previous_phlex_tui_component = Thread.current[:__phlex_tui_component__]
		Thread.current[:__phlex_tui_component__] = self

		yield_content { view_template(&) }
		tree
	ensure
		Thread.current[:__phlex_tui_component__] = previous_phlex_tui_component
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

	def box(*, **)
		node = Phlex::TUI::Box.new(*, parent: @tree.current_parent, **)
		@tree.attach(node)
		@tree.stack << node
		yield_content { yield } if block_given?
		nil
	ensure
		@tree.stack.pop
	end

	def render(component, &)
		case component
		in Phlex::TUI
			component.call(@tree, &)
		end
	end

	def popover(...)
		container(Phlex::TUI::Popover, ...)
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
