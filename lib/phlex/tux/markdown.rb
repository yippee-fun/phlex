# frozen_string_literal: true

class Phlex::Tux::Markdown < Phlex::TUI
	def initialize(content)
		unless defined?(Kramdown::Document)
			raise "Kramdown is not installed. Please run `bundle add kramdown` and require 'kramdown'."
		end

		@root = Kramdown::Document.new(content).root
		@stack = []
		@text_styles = [{}]
	end

	def view_template
		vstack(gap: 1) do
			visit(@root)
		end
	end

	def visit_root(node)
		visit_children(node)
	end

	def visit_header(node)
		paragraph(bold: true) do
			visit_children(node)
		end
	end

	def visit_text(node)
		emit_inline(node.value)
	end

	def visit_p(node)
		paragraph do
			visit_children(node)
		end
	end

	def visit_blank(node)
	end

	def visit_table(node)
		alignments = Array(node.options[:alignment])

		table do
			node.children.each do |section|
				visit_table_section(section, alignments)
			end
		end
	end

	def visit_table_section(node, alignments)
		header = node.type == :thead

		node.children.each do |row_node|
			visit_table_row(row_node, alignments, header:)
		end
	end

	def visit_table_row(node, alignments, header:)
		row(bold: header) do
			node.children.each_with_index do |cell_node, index|
				visit_table_cell(cell_node, index, alignments)
			end
		end
	end

	def visit_table_cell(node, index, alignments)
		col(border: :rounded, padding: [0, 1], align: :left, text_align: current_table_alignment(alignments, index)) do
			paragraph do
				visit_children(node)
			end
		end
	end

	def visit_em(node)
		with_text_style(italic: true) { visit_children(node) }
	end

	def visit_strong(node)
		with_text_style(bold: true) { visit_children(node) }
	end

	def visit_codespan(node)
		emit_inline(node.value, inverse: true)
	end

	def visit_a(node)
		visit_children(node)
	end

	def visit_html_element(node)
		case node.value
		in "u"
			with_text_style(underline: true) { visit_children(node) }
		in "del" | "s" | "strike"
			with_text_style(strikethrough: true) { visit_children(node) }
		else
			visit_children(node)
		end
	end

	def visit_img(node)
		alt = node.attr["alt"] || "image"
		emit_inline("[image: #{alt}]", italic: true)
	end

	def visit_entity(node)
		emit_inline(node.value.char)
	end

	def visit_br(node)
		emit_inline("\n")
	end

	def visit_codeblock(node)
		box(border: { left: :thin }) do
			box(padding: [0, 1]) do
				paragraph(node.value)
			end
		end
	end

	def visit_blockquote(node)
		box(border: { left: :thick }, padding: [0, 1], italic: true) do
			visit_children(node)
		end
	end

	def visit_hr(node)
		hr(border: :thin)
	end

	def visit_ul(node)
		table do
			node.children.each_with_index do |node, index|
				visit_ul_item(node, index)
			end
		end
	end

	def visit_ol(node)
		table do
			node.children.each_with_index do |node, index|
				visit_ol_item(node, index)
			end
		end
	end

	def visit_ul_item(node, index)
		row do
			col do
				"・"
			end

			col do
				visit_children(node)
			end
		end
	end

	def visit_ol_item(node, index)
		row(gap: 1) do
			col(text_align: :right) do
				"#{index + 1}."
			end

			col do
				visit_children(node)
			end
		end
	end

	def visit_children(node)
		node.children.each do |child|
			visit(child)
		end
	end

	def visit(node)
		@stack << node
		method_name = :"visit_#{node.type}"

		if respond_to?(method_name, true)
			__send__(method_name, node)
		else
			visit_children(node)
		end
	ensure
		@stack.pop
	end

	def current_list_type
		@stack.reverse_each do |element|
			return element.type if element.type == :ul || element.type == :ol
		end

		nil
	end

	def current_table_alignment(alignments, index)
		alignment = alignments.fetch(index, nil)

		case alignment
		in :center | :right
			alignment
		else
			:left
		end
	end

	def current_text_style
		@text_styles.last
	end

	def with_text_style(style)
		@text_styles << current_text_style.merge(style)
		yield
	ensure
		@text_styles.pop
	end

	def emit_inline(text, **overrides)
		options = current_text_style.merge(overrides)

		if Phlex::TUI::Paragraph === @tree.current_parent
			span(text, **options)
		else
			paragraph(text, **options)
		end
	end
end
