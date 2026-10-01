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

	[
		[:img, { srcset: ["a.png 1x", "b.png 2x"] }, %(<img srcset="a.png 1x, b.png 2x">)],
		[:img, { srcset: ["a.png 1x", ["b,c.png 2x"]] }, %(<img srcset="a.png 1x, b%2Cc.png 2x">)],
		[:img, { srcset: [] }, "<img>"],
		[:img, { srcset: "a.png 1x, b.png 2x" }, %(<img srcset="a.png 1x, b.png 2x">)],
		[:link, { media: ["screen", "print"], sizes: ["16x16", "32x32"] }, %(<link media="screen, print" sizes="16x16, 32x32">)],
		[:link, { rel: "preload", as: "image", imagesrcset: ["a.png 1x", "b.png 2x"] }, %(<link rel="preload" as="image" imagesrcset="a.png 1x, b.png 2x">)],
		[:link, { rel: :preload, as: :image, imagesrcset: ["a.png 1x", "b.png 2x"] }, %(<link rel="preload" as="image" imagesrcset="a.png 1x, b.png 2x">)],
		[:link, { "rel" => "preload", "as" => "image", :imagesrcset => ["a.png 1x", "b.png 2x"] }, %(<link rel="preload" as="image" imagesrcset="a.png 1x, b.png 2x">)],
		[:link, { rel: "stylesheet", as: "image", imagesrcset: ["a.png 1x", "b.png 2x"] }, %(<link rel="stylesheet" as="image" imagesrcset="a.png 1x b.png 2x">)],
		[:link, { rel: "preload", as: "script", imagesrcset: ["a.png 1x", "b.png 2x"] }, %(<link rel="preload" as="script" imagesrcset="a.png 1x b.png 2x">)],
		[:input, { type: "file", accept: ["image/webp", "image/avif"] }, %(<input type="file" accept="image/webp, image/avif">)],
		[:input, { type: :file, accept: ["image/webp", "image/avif"] }, %(<input type="file" accept="image/webp, image/avif">)],
		[:input, { "type" => "file", :accept => ["image/webp", "image/avif"] }, %(<input type="file" accept="image/webp, image/avif">)],
		[:input, { type: "text", accept: ["image/webp", "image/avif"] }, %(<input type="text" accept="image/webp image/avif">)],
	].each do |name, attributes, expected|
		test "<#{name}> normalizes #{attributes.inspect} like its registered method" do
			assert_equal HTMLComponent.call(name, **attributes), expected
			assert_equal Phlex.html { public_send(name, **attributes) }, expected
		end
	end

	test "element normalization happens before looking up cached attributes" do
		attributes = { srcset: ["a.png 1x", "b.png 2x"].freeze }.freeze

		assert_equal HTMLComponent.call(:div, **attributes), %(<div srcset="a.png 1x b.png 2x"></div>)
		2.times do
			assert_equal HTMLComponent.call(:img, **attributes), %(<img srcset="a.png 1x, b.png 2x">)
		end
		assert_equal HTMLComponent.call(:div, **attributes), %(<div srcset="a.png 1x b.png 2x"></div>)
		assert_equal attributes[:srcset], ["a.png 1x", "b.png 2x"]
	end

	test "element normalization errors close the opening tag like the registered method" do
		dynamic = Phlex::HTML.call do |component|
			assert_raises(Phlex::ArgumentError) { component.tag(:img, srcset: [Object.new]) }
		end

		registered = Phlex::HTML.call do |component|
			assert_raises(Phlex::ArgumentError) { component.img(srcset: [Object.new]) }
		end

		assert_equal dynamic, "<img>"
		assert_equal dynamic, registered
	end

	[
		[Phlex::HTML, :div, :span],
		[Phlex::HTML, :custom_tag, :span],
		[Phlex::HTML, :svg, :span],
		[Phlex::SVG, :g, :text],
		[Phlex::SVG, :custom_tag, :text],
	].each do |component_class, name, sibling|
		[{}, { id: "example" }].each do |attributes|
			test "#{component_class} #{name} closes when its block raises with #{attributes.inspect}" do
				output = component_class.call do |component|
					error = assert_raises RuntimeError do
						component.tag(name, **attributes) do |content|
							content.plain "before"
							raise "example"
						end
					end

					assert_equal error.message, "example"
					component.tag(sibling) { "after" }
				end

				tag = name.name.tr("_", "-")
				attribute = attributes.empty? ? "" : ' id="example"'
				assert_equal output, "<#{tag}#{attribute}>before</#{tag}><#{sibling}>after</#{sibling}>"
			end
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
end
