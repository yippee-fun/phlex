# frozen_string_literal: true

class TagTest < Quickdraw::Test
	class HTMLComponent < Phlex::HTML
		def initialize(tag, **attributes)
			@tag = tag
			@attributes = attributes
		end

		def view_template(&)
			tag(@tag, **@attributes, &)
		end
	end

	class SVGComponent < Phlex::SVG
		def initialize(tag, **attributes)
			@tag = tag
			@attributes = attributes
		end

		def view_template(&)
			tag(@tag, **@attributes, &)
		end
	end

	Phlex::HTML::VoidElements.__registered_elements__.each do |method_name, tag|
		test "<#{tag}> HTML tag without attributes" do
			output = HTMLComponent.call(tag.to_sym)

			assert_equal output, <<~HTML.strip
    <#{tag}>
HTML
		end

		test "<#{tag}> HTML tag with attributes" do
			output = HTMLComponent.call(tag.to_sym, class: "class", id: "id", disabled: true)

			assert_equal output, <<~HTML.strip
    <#{tag} class="class" id="id" disabled>
HTML
		end

		test "<#{tag}> HTML tag with content" do
			error = assert_raises Phlex::ArgumentError do
				HTMLComponent.call(tag.to_sym) do
					"Hello, world!"
				end
			end

			assert_equal error.message, "Void elements cannot have content blocks."
		end
	end

	Phlex::HTML::StandardElements.__registered_elements__.each do |method_name, tag|
		test "<#{tag}> HTML tag without attributes" do
			output = HTMLComponent.call(tag.to_sym)

			assert_equal output, <<~HTML.strip
    <#{tag}></#{tag}>
HTML
		end

		test "<#{tag}> HTML tag with attributes" do
			output = HTMLComponent.call(tag.to_sym, class: "class", id: "id", disabled: true)

			assert_equal output, <<~HTML.strip
    <#{tag} class="class" id="id" disabled></#{tag}>
HTML
		end

		test "<#{tag}> HTML tag with content" do
			output = HTMLComponent.call(tag.to_sym) do
				"Hello, world!"
			end

			assert_equal output, <<~HTML.strip
    <#{tag}>Hello, world!</#{tag}>
HTML
		end

		test "<#{tag}> HTML tag with content and attributes" do
			output = HTMLComponent.call(tag.to_sym, class: "class", id: "id", disabled: true) do
				"Hello, world!"
			end

			assert_equal output, <<~HTML.strip
    <#{tag} class="class" id="id" disabled>Hello, world!</#{tag}>
HTML
		end
	end

	Phlex::SVG::StandardElements.__registered_elements__.each do |method_name, tag|
		test "<#{tag}> SVG tag without attributes" do
			output = SVGComponent.call(tag.to_sym)

			assert_equal output, <<~HTML.strip
    <#{tag}></#{tag}>
HTML
		end

		test "<#{tag}> SVG tag with attributes" do
			output = SVGComponent.call(tag.to_sym, class: "class", id: "id", disabled: true)

			assert_equal output, <<~HTML.strip
    <#{tag} class="class" id="id" disabled></#{tag}>
HTML
		end

		test "<#{tag}> SVG tag with content" do
			output = SVGComponent.call(tag.to_sym) do
				"Hello, world!"
			end

			assert_equal output, <<~HTML.strip
    <#{tag}>Hello, world!</#{tag}>
HTML
		end

		test "<#{tag}> SVG tag with content and attributes" do
			output = SVGComponent.call(tag.to_sym, class: "class", id: "id", disabled: true) do
				"Hello, world!"
			end

			assert_equal output, <<~HTML.strip
    <#{tag} class="class" id="id" disabled>Hello, world!</#{tag}>
HTML
		end
	end

	test "svg tag in HTML" do
		output = HTMLComponent.call(:svg) do |svg|
			svg.circle(cx: 50, cy: 50, r: 40, fill: "red")
		end

		assert_equal output, <<~HTML.strip
   <svg><circle cx="50" cy="50" r="40" fill="red"></circle></svg>
HTML
	end

	test "with invalid tag name" do
		error = assert_raises Phlex::ArgumentError do
			HTMLComponent.call(:invalidtag)
		end

		assert_equal error.message, "Invalid HTML tag: invalidtag"
	end

	test "with invalid tag name input type" do
		error = assert_raises Phlex::ArgumentError do
			HTMLComponent.call("div")
		end

		assert_equal error.message, "Expected the tag name to be a Symbol."
	end

	test "with custom tag name" do
		output = HTMLComponent.call(:custom_tag)

		assert_equal output, <<~HTML.strip
   <custom-tag></custom-tag>
HTML
	end
end
