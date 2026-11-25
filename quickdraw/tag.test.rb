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

	Phlex::HTML::VoidElements.__registered_elements__.reject { |_, tag| Phlex::HTML::UNSAFE_TAGS.include?(tag) }.each do |method_name, tag|
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

	Phlex::HTML::StandardElements.__registered_elements__.reject { |_, tag| Phlex::HTML::UNSAFE_TAGS.include?(tag) }.each do |method_name, tag|
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

	Phlex::SVG::StandardElements.__registered_elements__.reject { |_, tag| Phlex::SVG::UNSAFE_TAGS.include?(tag) }.each do |method_name, tag|
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

	test "with unsafe custom tag name containing a space" do
		error = assert_raises Phlex::ArgumentError do
			HTMLComponent.call(:"x-widget onclick=alert(1)")
		end

		assert_equal error.message, "Invalid HTML tag: x-widget onclick=alert(1)"
	end

	test "with unsafe custom tag name containing special characters" do
		error = assert_raises Phlex::ArgumentError do
			HTMLComponent.call(:"x-widget>")
		end

		assert_equal error.message, "Invalid HTML tag: x-widget>"
	end

	test "with unsafe SVG custom tag name containing a space" do
		error = assert_raises Phlex::ArgumentError do
			SVGComponent.call(:"x-widget onclick=alert(1)")
		end

		assert_equal error.message, "Invalid SVG tag: x-widget onclick=alert(1)"
	end

	# The name passed to `tag` may come from a user.
	test "tag won't render elements whose content or attributes run as code" do
		%i[script style base].each do |name|
			error = assert_raises(Phlex::ArgumentError) { HTMLComponent.call(name) { "alert(1)" } }
			assert_equal error.message, "`tag` can't render <#{name}>. Call `#{name}` directly instead."
		end

		assert_raises(Phlex::ArgumentError) { HTMLComponent.call(:script, src: "/app.js") }
		assert_raises(Phlex::ArgumentError) { HTMLComponent.call(:base, href: "/") }

		svg = Class.new(Phlex::SVG) { define_method(:initialize) { |name| @name = name }; define_method(:view_template) { tag(@name) { "alert(1)" } } }
		%i[script style].each { |name| assert_raises(Phlex::ArgumentError) { svg.new(name).call } }

		# Calling the element directly still works.
		assert_equal Class.new(Phlex::HTML) { define_method(:view_template) { script { "" } } }.call, "<script></script>"
	end

	test "tag closes its tags when its attributes or content raise" do
		html = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				[-> { tag(:div, href: { _: "javascript:x" }) }, -> { tag(:div, href: { _: "javascript:x" }) { "c" } }, -> { tag(:img, src: { _: "javascript:x" }) }, -> { tag(:"x-y") { raise Phlex::ArgumentError } }].each do |call|
					call.()
				rescue Phlex::ArgumentError
					nil
				end
				plain "|"
			end
		end

		assert_equal html.call, "<div></div><div><img><x-y></x-y>|"
	end

	test "head flushes like its element method" do
		component = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				tag(:head) { "x" }
				body
			end
		end

		chunks = []
		component.new.call(chunks)

		assert_equal chunks, ["<head>x</head>", "<body></body>"]
	end
end
