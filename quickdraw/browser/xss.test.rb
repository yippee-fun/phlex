# frozen_string_literal: true

class XSSTest < Quickdraw::Test
	include Quickdraw::Browser

	ASCII_CHARS = (0..127).map(&:chr)
	XSS_STRINGS = File.readlines(File.expand_path("../../fixtures/xss.txt", __dir__), encoding: Encoding::UTF_8)

	# Runs in every frame, and in the page's head. Dialogs are posted to the top
	# window, which records them, since frames may be cross-origin. Links that
	# aren't javascript: are kept from navigating away, which would end the
	# test's evaluate.
	HARNESS = <<~JS
		window.alert = window.confirm = window.prompt = (message) => { window.top.postMessage({ dialog: String(message) }, "*") }

		if (window === window.top) {
			window.dialogs = []
			addEventListener("message", (event) => { if (event.data?.dialog) window.dialogs.push(event.data.dialog) })

			addEventListener("click", (event) => {
				const link = event.target.closest("a")
				// An SVG link's href can be animated, so it's read as the browser will use it.
				const href = link instanceof SVGAElement ? link.href.animVal : (link?.getAttribute("href") ?? link?.getAttribute("xlink:href"))
				if (href == null) return

				try {
					if (new URL(href, document.baseURI).protocol !== "javascript:") event.preventDefault()
				} catch {
					event.preventDefault()
				}
			}, true)

			// Clicks every element, then an HTML and an SVG javascript: link of its
			// own, and waits for their dialogs, so the links clicked before them have run.
			window.clickEverything = async () => {
				const controls = document.createElement("div")
				controls.innerHTML = `<a href="javascript:alert('control')">x</a><svg><a href="javascript:alert('control')"><text>x</text></a></svg>`
				const nodes = [...document.body.querySelectorAll("*"), ...controls.querySelectorAll("a")]
				document.body.append(controls)

				for (const node of nodes) {
					node.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }))
				}

				const deadline = Date.now() + 5000

				while (window.dialogs.filter((message) => message === "control").length < 2) {
					if (Date.now() > deadline) throw new Error("The control links’ dialogs never opened.")
					await new Promise((resolve) => setTimeout(resolve, 10))
				}

				return window.dialogs.filter((message) => message !== "control")
			}
		}
	JS

	class Page < Phlex::HTML
		def view_template
			doctype

			html do
				head do
					meta(charset: "utf-8")
					script { raw(safe(HARNESS)) }
				end

				body { content }
			end
		end

		private def ignore_warnings
			yield
		rescue Phlex::ArgumentError
			nil
		end
	end

	class JavaScriptLinks < Page
		def initialize(char)
			@char = char
		end

		private def content
			a(href: "javascript:alert(1)") { "x" }
			a(href: "Javascript:alert(1)") { "x" }
			a(href: "javascript:javascript:alert(1)") { "x" }
			a(href: "javascript:javascript:javascript:alert(1)") { "x" }
			a(href: "javascript:Javascript:alert(1)") { "x" }
			a(href: "Javascript:javascript:alert(1)") { "x" }

			["javascript:", "Javascript:"].product([@char, @char * 2]) do |scheme, inserted|
				0.upto(scheme.length) do |index|
					a(href: "#{scheme.dup.insert(index, inserted)}alert(1)") { "x" }
				end
			end
		end
	end

	class EventAttributes < Page
		def initialize(char)
			@char = char
		end

		private def content
			[@char, @char * 2].each do |inserted|
				0.upto("onclick".length) do |index|
					name = "onclick".dup.insert(index, inserted)
					ignore_warnings { div(name => "alert(1)") { "x" } }
					ignore_warnings { div(name.to_sym => "alert(1)") { "x" } }
				end
			end
		end
	end

	class XSSWithStrings < Page
		private def content
			XSS_STRINGS.each do |line|
				div(class: line) { line }
				svg do |s|
					s.cdata(line)
					s.cdata { line }
				end
			end
		end
	end

	class XSSWithSymbols < Page
		private def content
			XSS_STRINGS.each do |line|
				div(class: line.to_sym) { line.to_sym }
			end
		end
	end

	class EncodedJavaScriptLinks < Page
		private def content
			ignore_warnings { a(href: "javascript&#58;alert(1)") { "x" } }
			ignore_warnings { a(href: "java&#x73;cript:alert(1)") { "x" } }
			ignore_warnings { a(href: "javascript&#58alert(1)") { "x" } }
			ignore_warnings { a(href: "java&#x73cript:alert(1)") { "x" } }
			ignore_warnings { a(href: "javascript&colon;alert(1)") { "x" } }
		end
	end

	class InjectedAttributeNames < Page
		private def content
			ignore_warnings { div("x onclick": "alert(1)") { "x" } }
			ignore_warnings { div("x/onclick": "alert(1)") { "x" } }
		end
	end

	class UnsafeCustomTagNames < Page
		private def content
			ignore_warnings { tag(:"x-widget onclick=alert(1)") { "x" } }
		end
	end

	class UnsafeSvgXlinkHref < Page
		private def content
			svg do |s|
				ignore_warnings { s.a("xlink:href": "javascript:alert(1)") { "x" } }
				ignore_warnings { s.a("xlink:href": "javascript&colon;alert(1)") { "x" } }
				ignore_warnings { s.a("xlink:href": "javascript&#58alert(1)") { "x" } }
			end
		end
	end

	# SVG animations write `to`, `from` and `values` to the attribute named by
	# `attributeName`, so a link's href can become a script URL after it's parsed.
	class SvgAnimationReferences < Page
		private def content
			svg do |s|
				s.a(href: "#safe") { s.set(attributeName: "href", to: "javascript:alert(1)"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", to: "javascript:alert(2)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", from: "javascript:alert(3)", to: "#safe", dur: "100s"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", values: "javascript:alert(4)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", values: "#safe;javascript:alert(5)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", values: "#safe&#59;javascript:alert(6)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", values: "#safe&semi;javascript:alert(7)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.animate(attributeName: "href", by: "javascript:alert(8)", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.set("attributename" => "href", :to => "javascript:alert(9)"); s.text(y: 10) { "x" } }
				s.a(href: "#safe") { s.set(attributeName: "href", to: "javascript&colon;alert(10)"); s.text(y: 10) { "x" } }
				# References the decoder removes but browsers keep, with the `;` they hide.
				["&zz;", "&TAB;", "&ampx;", "&#38;zz;"].each_with_index do |reference, index|
					s.a(href: "#safe") { s.animate(attributeName: "href", values: "#safe#{reference}javascript:alert(#{12 + index})", dur: "0.01s", fill: "freeze"); s.text(y: 10) { "x" } }
				end
				s.a(id: "target", href: "#safe") { s.text(y: 10) { "x" } }
				s.set(href: "#target", attributeName: "href", to: "javascript:alert(11)")
			end
		end
	end

	# An element whose content isn't parsed as markup, or a comment, ends at its
	# end tag or `-->` even inside an attribute value.
	class RawTextBreakouts < Page
		private def content
			noscript { img(alt: "</noscript><img src=x onerror=alert(1)>") }
			comment { span(title: "--><img src=x onerror=alert(2)>") }
			textarea { span(title: "</textarea><img src=x onerror=alert(3)>") }
			noscript { div(data: { x: "</noscript><img src=x onerror=alert(4)>" }) }
			noscript { div(class: ["</noscript><img src=x onerror=alert(5)>"]) }
			noscript { div(style: { content: "'</noscript><img src=x onerror=alert(6)>'" }) }
			noscript { div(title: safe("</noscript><img src=x onerror=alert(7)>")) }
		end
	end

	# A user-provided tag name with user-provided content or attributes.
	class UserTagNames < Page
		private def content
			%i[script style base].each do |name|
				ignore_warnings { tag(name) { "alert(1)" } }
				ignore_warnings { tag(name, src: "data:text/javascript,alert(2)", href: "data:text/javascript,alert(3)") }
			end

			svg do |s|
				%i[script style].each { |name| ignore_warnings { s.tag(name) { "alert(4)" } } }
			end
		end
	end

	test "user-provided tag names" do
		assert_no_dialogs UserTagNames.new
	end

	test "SVG animation references" do
		assert_no_dialogs SvgAnimationReferences.new
	end

	test "attribute values in raw text elements and comments" do
		assert_no_dialogs RawTextBreakouts.new
	end

	ASCII_CHARS.each do |char|
		test "javascript: links with #{char.inspect}" do
			assert_no_dialogs JavaScriptLinks.new(char)
		end

		test "event attributes with #{char.inspect}" do
			assert_no_dialogs EventAttributes.new(char)
		end
	end

	test "XSS strings" do
		assert_no_dialogs XSSWithStrings.new
	end

	test "XSS symbols" do
		assert_no_dialogs XSSWithSymbols.new
	end

	test "encoded javascript: links" do
		assert_no_dialogs EncodedJavaScriptLinks.new
	end

	test "injected attribute names" do
		assert_no_dialogs InjectedAttributeNames.new
	end

	test "unsafe custom tag names" do
		assert_no_dialogs UnsafeCustomTagNames.new
	end

	test "unsafe SVG xlink:href" do
		assert_no_dialogs UnsafeSvgXlinkHref.new
	end

	private def assert_no_dialogs(component)
		page.add_init_script(HARNESS)
		page.set_content(component.call)
		assert_equal page.evaluate("clickEverything()"), []
	end
end
