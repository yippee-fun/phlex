# frozen_string_literal: true

require "sgml_helper"

class AttributesTest < Quickdraw::Test
	include SGMLHelper

	test "id attributes must be lower case symbols" do
		assert_raises(Phlex::ArgumentError) { phlex { div("id" => "abc") } }
		assert_raises(Phlex::ArgumentError) { phlex { div("ID" => "abc") } }
		assert_raises(Phlex::ArgumentError) { phlex { div(:ID => "abc") } }

		output = phlex { div(id: "abc") }
		assert_equal output, %(<div id="abc"></div>)
	end

	test "*invalid*, _" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div(Object.new => "abc") }
		end

		assert_equal error.message, "Attribute keys should be Strings or Symbols."
	end

	test "unsafe event attribute" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("onclick" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: onclick."
	end

	test "data with hash" do
		data = phlex { div(data: { attr: "test" }) }
		assert_equal data, %(<div data-attr="test"></div>)
	end

	test "data with object which responds to to_h" do
		data = phlex { div(data: Data.define(:attr).new(attr: "test")) }
		assert_equal data, %(<div data-attr="test"></div>)
	end

	test "href with hash" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { a(href: {}) }
		end

		assert_equal error.message, "Invalid attribute value for href: #{{}.inspect}."
	end

	test "unsafe href attribute" do
		[
			phlex { a(href: "javascript:alert('hello')") },
			phlex { a(href: "Javascript:alert('hello')") },
			phlex { a("href" => "javascript:alert('hello')") },
			phlex { a("Href" => "javascript:alert('hello')") },
			phlex { a("Href" => "javascript:javascript:alert('hello')") },
			phlex { a(href: " \t\njavascript:alert('hello')") },
			phlex { a(href: "java&#x73;cript:alert(1)") },
			phlex { a(href: "javascript&#58;alert(1)") },
			phlex { a(href: "java&#115;cript:alert(1)") },
			phlex { a(href: "&#106;avascript:alert(1)") },
			phlex { a(href: "javascript&#58alert(1)") },
			phlex { a(href: "javascript&colon;alert(1)") },
		].each do |output|
			assert_equal output, %(<a></a>)
		end
	end

	test "unsafe xlink:href attribute" do
		[
			phlex(Phlex::SVG) { a("xlink:href": "javascript:alert(1)") { "x" } },
			phlex(Phlex::SVG) { a("xlink:href": "javascript&colon;alert(1)") { "x" } },
			phlex(Phlex::SVG) { a("xlink:href": "javascript&#58alert(1)") { "x" } },
		].each do |output|
			assert_equal output, %(<a>x</a>)
		end
	end

	test "unsafe attribute name <" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("<" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: <."
	end

	test "unsafe attribute name >" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div(">" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: >."
	end

	test "unsafe attribute name &" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("&" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: &."
	end

	test "unsafe attribute name '" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("'" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: '."
	end

	test "unsafe attribute name \"" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div('"' => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: \"."
	end

	test "unsafe attribute name with space (String)" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("foo bar" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: foo bar."
	end

	test "unsafe attribute name with space (Symbol)" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("foo bar": true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: foo bar."
	end

	test "unsafe attribute name with slash (String)" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("foo/bar" => true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: foo/bar."
	end

	test "unsafe attribute name with slash (Symbol)" do
		error = assert_raises(Phlex::ArgumentError) do
			phlex { div("foo/bar": true) }
		end

		assert_equal error.message, "Unsafe attribute name detected: foo/bar."
	end

	test "_, nil" do
		output = phlex { div(attribute: nil) }
		assert_equal output, %(<div></div>)
	end

	test "_, true" do
		output = phlex { div(attribute: true) }
		assert_equal output, %(<div attribute></div>)
	end

	test "_, false" do
		output = phlex { div(attribute: false) }
		assert_equal output, %(<div></div>)
	end

	test "_, String" do
		with_empty_string = phlex { div(attribute: "") }
		assert_equal with_empty_string, %(<div attribute=""></div>)

		with_regular_string = phlex { div(attribute: "test") }
		assert_equal with_regular_string, %(<div attribute="test"></div>)

		with_underscores = phlex { div(attribute: "with_underscores") }
		assert_equal with_underscores, %(<div attribute="with_underscores"></div>)

		with_dashes = phlex { div(attribute: "with-dashes") }
		assert_equal with_dashes, %(<div attribute="with-dashes"></div>)

		with_spaces = phlex { div(attribute: "with spaces") }
		assert_equal with_spaces, %(<div attribute="with spaces"></div>)

		with_single_quotes = phlex { div(attribute: "with 'single quotes'") }
		assert_equal with_single_quotes, %(<div attribute="with 'single quotes'"></div>)

		with_html = phlex { div(attribute: "with <html>") }
		assert_equal with_html, %(<div attribute="with <html>"></div>)

		with_double_quotes = phlex { div(attribute: 'with "double quotes"') }
		assert_equal with_double_quotes, %(<div attribute="with &quot;double quotes&quot;"></div>)
	end

	test "_, Symbol" do
		empty_symbol = phlex { div(attribute: :"") }
		assert_equal empty_symbol, %(<div attribute=""></div>)

		simple_symbol = phlex { div(attribute: :test) }
		assert_equal simple_symbol, %(<div attribute="test"></div>)

		symbol_with_underscores = phlex { div(attribute: :with_underscores) }
		assert_equal symbol_with_underscores, %(<div attribute="with-underscores"></div>)

		symbol_with_dashes = phlex { div(attribute: :"with-dashes") }
		assert_equal symbol_with_dashes, %(<div attribute="with-dashes"></div>)

		symbol_with_spaces = phlex { div(attribute: :"with spaces") }
		assert_equal symbol_with_spaces, %(<div attribute="with spaces"></div>)

		symbol_with_single_quotes = phlex { div(attribute: :"with 'single quotes'") }
		assert_equal symbol_with_single_quotes, %(<div attribute="with 'single quotes'"></div>)

		symbol_with_html = phlex { div(attribute: :"with <html>") }
		assert_equal symbol_with_html, %(<div attribute="with <html>"></div>)

		symbol_with_double_quotes = phlex { div(attribute: :'with "double quotes"') }
		assert_equal symbol_with_double_quotes, %(<div attribute="with &quot;double quotes&quot;"></div>)
	end

	test "_, Integer" do
		output = phlex { div(attribute: 0) }
		assert_equal output, %(<div attribute="0"></div>)

		output = phlex { div(attribute: 42) }
		assert_equal output, %(<div attribute="42"></div>)
	end

	test "_, Float" do
		output = phlex { div(attribute: 0.0) }
		assert_equal output, %(<div attribute="0.0"></div>)

		output = phlex { div(attribute: 42.0) }
		assert_equal output, %(<div attribute="42.0"></div>)

		output = phlex { div(attribute: 1.234) }
		assert_equal output, %(<div attribute="1.234"></div>)
	end

	test "_, Date" do
		output = phlex { div(attribute: Date.new(2023, 1, 15)) }
		assert_equal output, %(<div attribute="2023-01-15"></div>)
	end

	test "_, Time" do
		output = phlex { div(attribute: Time.new(2023, 1, 15, 12, 30, 45, "+00:00")) }
		assert_equal output, %(<div attribute="2023-01-15T12:30:45+00:00"></div>)
	end

	test "_, *invalid*" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(attribute: Object.new) }
		end
	end

	test "_, Array" do
		output = phlex { div(attribute: []) }
		assert_equal output, %(<div></div>)
	end

	test "_, Array(Array)" do
		output = phlex { div(attribute: [[], [], []]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Array(nil)" do
		output = phlex { div(attribute: [nil, nil, nil]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Array(Array(nil))" do
		output = phlex { div(attribute: [[nil, nil], [nil, nil]]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Array(Array(nil), nil)" do
		output = phlex { div(attribute: [[nil, nil], nil]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Array(String)" do
		output = phlex { div(attribute: ["Hello", "World"]) }
		assert_equal output, %(<div attribute="Hello World"></div>)

		output = phlex { div(attribute: ["with_underscores", "with-dashes", "with spaces"]) }
		assert_equal output, %(<div attribute="with_underscores with-dashes with spaces"></div>)

		output = phlex { div(attribute: ["with 'single quotes'", 'with "double quotes"']) }
		assert_equal output, %(<div attribute="with 'single quotes' with &quot;double quotes&quot;"></div>)
	end

	test "_, Array(Symbol)" do
		output = phlex { div(attribute: [:hello, :world]) }
		assert_equal output, %(<div attribute="hello world"></div>)

		output = phlex { div(attribute: [:with_underscores, :"with-dashes", :"with spaces"]) }
		assert_equal output, %(<div attribute="with-underscores with-dashes with spaces"></div>)

		output = phlex { div(attribute: [:with, :"'single quotes'", :'"double quotes"']) }
		assert_equal output, %(<div attribute="with 'single quotes' &quot;double quotes&quot;"></div>)
	end

	test "_, Array(Integer)" do
		output = phlex { div(attribute: [0, 42]) }
		assert_equal output, %(<div attribute="0 42"></div>)
	end

	test "_, Array(Float)" do
		output = phlex { div(attribute: [0.0, 42.0, 1.234]) }
		assert_equal output, %(<div attribute="0.0 42.0 1.234"></div>)
	end

	test "_, Array(Phlex::SGML::SafeObject)" do
		output = phlex { div(attribute: [Phlex::SGML::SafeValue.new("Hello")]) }
		assert_equal output, %(<div attribute="Hello"></div>)
	end

	test "_, Array(String | Array)" do
		output = phlex { div(attribute: ["hello", ["world"]]) }
		assert_equal output, %(<div attribute="hello world"></div>)
	end

	test "_, Array(Array | String)" do
		output = phlex { div(attribute: [["hello"], "world"]) }
		assert_equal output, %(<div attribute="hello world"></div>)
	end

	test "_, Array(String | EmptyArray)" do
		output = phlex { div(attribute: ["hello", []]) }
		assert_equal output, %(<div attribute="hello"></div>)
	end

	test "_, Array(*invalid*)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(attribute: [Object.new]) }
		end
	end

	test "_, Hash(Symbol, _)" do
		output = phlex { div(attribute: { a_b_c: "world" }) }
		assert_equal output, %(<div attribute-a-b-c="world"></div>)

		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { :'"' => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { :"'" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { :"&" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { :"<" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { :">" => "a" }) } }
	end

	test "_, Hash(String, _)" do
		output = phlex { div(attribute: { "a_b_c" => "world" }) }
		assert_equal output, %(<div attribute-a_b_c="world"></div>)

		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { '"' => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { "'" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { "&" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { "<" => "a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { ">" => "a" }) } }
	end

	test "_, Hash(:_, _)" do
		by_itself = phlex { div(attribute: { _: "world" }) }
		assert_equal by_itself, %(<div attribute="world"></div>)

		with_others = phlex { div(data: { _: "test", controller: "hello" }) }
		assert_equal with_others, %(<div data="test" data-controller="hello"></div>)
	end

	test "_, Hash(*invalid*, _)" do
		assert_raises(Phlex::ArgumentError) { phlex { div(attribute: { Object.new => "a" }) } }
	end

	test "_, Hash(_, String)" do
		with_underscores = phlex { div(data: { controller: "with_underscores" }) }
		assert_equal with_underscores, %(<div data-controller="with_underscores"></div>)

		with_dashes = phlex { div(data: { controller: "with-dashes" }) }
		assert_equal with_dashes, %(<div data-controller="with-dashes"></div>)

		with_spaces = phlex { div(data: { controller: "with spaces" }) }
		assert_equal with_spaces, %(<div data-controller="with spaces"></div>)

		with_single_quotes = phlex { div(data: { controller: "with 'single quotes'" }) }
		assert_equal with_single_quotes, %(<div data-controller="with 'single quotes'"></div>)

		with_html = phlex { div(data: { controller: "with <html>" }) }
		assert_equal with_html, %(<div data-controller="with <html>"></div>)

		with_double_quotes = phlex { div(data: { controller: 'with "double quotes"' }) }
		assert_equal with_double_quotes, %(<div data-controller="with &quot;double quotes&quot;"></div>)
	end

	test "_, Hash(_, Symbol)" do
		output = phlex { div(data: { controller: :with_underscores }) }
		assert_equal output, %(<div data-controller="with-underscores"></div>)

		output = phlex { div(data: { controller: :"with-dashes" }) }
		assert_equal output, %(<div data-controller="with-dashes"></div>)

		output = phlex { div(data: { controller: :"with spaces" }) }
		assert_equal output, %(<div data-controller="with spaces"></div>)

		output = phlex { div(data: { controller: :"with 'single quotes'" }) }
		assert_equal output, %(<div data-controller="with 'single quotes'"></div>)

		output = phlex { div(data: { controller: :"with <html>" }) }
		assert_equal output, %(<div data-controller="with <html>"></div>)

		output = phlex { div(data: { controller: :'with "double quotes"' }) }
		assert_equal output, %(<div data-controller="with &quot;double quotes&quot;"></div>)
	end

	test "_, Hash(_, Integer)" do
		output = phlex { div(data: { controller: 42 }) }
		assert_equal output, %(<div data-controller="42"></div>)

		output = phlex { div(data: { controller: 1_234 }) }
		assert_equal output, %(<div data-controller="1234"></div>)

		output = phlex { div(data: { controller: 0 }) }
		assert_equal output, %(<div data-controller="0"></div>)
	end

	test "_, Hash(_, Float)" do
		output = phlex { div(data: { controller: 42.0 }) }
		assert_equal output, %(<div data-controller="42.0"></div>)

		output = phlex { div(data: { controller: 1.234 }) }
		assert_equal output, %(<div data-controller="1.234"></div>)

		output = phlex { div(data: { controller: 0.0 }) }
		assert_equal output, %(<div data-controller="0.0"></div>)
	end

	test "_, Hash(_, Array)" do
		output = phlex { div(data: { controller: [1, 2, 3] }) }
		assert_equal output, %(<div data-controller="1 2 3"></div>)
	end

	test "_, Hash(_, Set)" do
		output = phlex { div(data: { controller: Set[1, 2, 3] }) }
		assert_equal output, %(<div data-controller="1 2 3"></div>)
	end

	test "_, Hash(_, Hash)" do
		output = phlex { div(data: { controller: { hello: "world" } }) }
		assert_equal output, %(<div data-controller-hello="world"></div>)
	end

	test "_, Hash(_, Hash(_, nil)" do
		output = phlex { div(data: { controller: { hello: nil } }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Phlex::SGML::SafeObject)" do
		output = phlex { div(data: { controller: Phlex::SGML::SafeValue.new("Hello") }) }
		assert_equal output, %(<div data-controller="Hello"></div>)
	end

	test "_, Hash(_, false)" do
		output = phlex { div(data: { controller: false }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, nil)" do
		output = phlex { div(data: { controller: nil }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Array)" do
		output = phlex { div(data: { action: [] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Array(nil))" do
		output = phlex { div(data: { action: [nil] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Set)" do
		output = phlex { div(data: { action: Set[] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Set(Set))" do
		output = phlex { div(data: { action: Set[Set[]] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Set(nil))" do
		output = phlex { div(data: { action: Set[nil] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, Set(Set(nil)))" do
		output = phlex { div(data: { action: Set[Set[nil]] }) }
		assert_equal output, %(<div></div>)
	end

	test "_, Hash(_, *invalid*)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(data: { controller: Object.new }) }
		end
	end

	test "_, Set" do
		output = phlex { div(attribute: Set[]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(nil)" do
		output = phlex { div(attribute: Set[nil, nil, nil]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(Set)" do
		output = phlex { div(attribute: Set[Set[]]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(Set(nil))" do
		output = phlex { div(attribute: Set[Set[nil, nil, nil]]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(Set, nil)" do
		output = phlex { div(attribute: Set[Set[], nil]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(Set(nil), nil)" do
		output = phlex { div(attribute: Set[Set[nil], nil]) }
		assert_equal output, %(<div></div>)
	end

	test "_, Set(String)" do
		output = phlex { div(attribute: Set["Hello", "World"]) }
		assert_equal output, %(<div attribute="Hello World"></div>)

		output = phlex { div(attribute: Set["with_underscores", "with-dashes", "with spaces"]) }
		assert_equal output, %(<div attribute="with_underscores with-dashes with spaces"></div>)

		output = phlex { div(attribute: Set["with 'single quotes'", 'with "double quotes"']) }
		assert_equal output, %(<div attribute="with 'single quotes' with &quot;double quotes&quot;"></div>)
	end

	test "_, Set(Symbol)" do
		output = phlex { div(attribute: Set[:hello, :world]) }
		assert_equal output, %(<div attribute="hello world"></div>)

		output = phlex { div(attribute: Set[:with_underscores, :"with-dashes", :"with spaces"]) }
		assert_equal output, %(<div attribute="with-underscores with-dashes with spaces"></div>)

		output = phlex { div(attribute: Set[:with, :"single quotes", :'"double quotes"']) }
		assert_equal output, %(<div attribute="with single quotes &quot;double quotes&quot;"></div>)
	end

	test "_, Set(Integer)" do
		output = phlex { div(attribute: Set[0, 42]) }
		assert_equal output, %(<div attribute="0 42"></div>)
	end

	test "_, Set(Float)" do
		output = phlex { div(attribute: Set[0.0, 42.0, 1.234]) }
		assert_equal output, %(<div attribute="0.0 42.0 1.234"></div>)
	end

	test "_, Set(Phlex::SGML::SafeObject)" do
		output = phlex do
			div(attribute: Set[Phlex::SGML::SafeValue.new("Hello")])
		end

		assert_equal output, %(<div attribute="Hello"></div>)
	end

	test "_, Set(*invalid*)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(attribute: Set[Object.new]) }
		end
	end

	test ":style, Array(nil)" do
		output = phlex { div(style: [nil, nil, nil]) }
		assert_equal output, %(<div style=""></div>)
	end

	test ":style, Array(Symbol)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(style: [:color_blue]) }
		end
	end

	test ":style, Array(String)" do
		output = phlex { div(style: ["color: blue;", "font-weight: bold"]) }
		assert_equal output, %(<div style="color: blue; font-weight: bold;"></div>)

		output = phlex { div(style: ["font-family: 'MonoLisa'"]) }
		assert_equal output, %(<div style="font-family: 'MonoLisa';"></div>)

		output = phlex { div(style: ['font-family: "MonoLisa"']) }
		assert_equal output, %(<div style="font-family: &quot;MonoLisa&quot;;"></div>)
	end

	test ":style, Array(Phlex::SGML::SafeObject)" do
		output = phlex { div(style: [Phlex::SGML::SafeValue.new("color: blue")]) }
		assert_equal output, %(<div style="color: blue;"></div>)

		output = phlex { div(style: [Phlex::SGML::SafeValue.new("font-weight: bold;")]) }
		assert_equal output, %(<div style="font-weight: bold;"></div>)
	end

	test ":style, Array(Hash)" do
		output = phlex { div(style: [{ color: "blue" }, { font_weight: "bold", line_height: 1.5 }]) }
		assert_equal output, %(<div style="color: blue; font-weight: bold; line-height: 1.5;"></div>)
	end

	test ":style, Set(nil)" do
		output = phlex { div(style: Set[nil]) }
		assert_equal output, %(<div style=""></div>)
	end

	test ":style, Set(String)" do
		output = phlex { div(style: Set["color: blue"]) }
		assert_equal output, %(<div style="color: blue;"></div>)
	end

	test ":style, Hash(Symbol, String)" do
		output = phlex { div(style: { color: "blue", font_weight: "bold" }) }
		assert_equal output, %(<div style="color: blue; font-weight: bold;"></div>)
	end

	test ":style, Hash(Symbol, Integer)" do
		output = phlex { div(style: { line_height: 2 }) }
		assert_equal output, %(<div style="line-height: 2;"></div>)
	end

	test ":style, Hash(Symbol, Float)" do
		output = phlex { div(style: { line_height: 1.5 }) }
		assert_equal output, %(<div style="line-height: 1.5;"></div>)
	end

	test ":style, Hash(Symbol, Symbol)" do
		output = phlex { div(style: { flex_direction: :column_reverse }) }
		assert_equal output, %(<div style="flex-direction: column-reverse;"></div>)

		output = phlex { div(style: { flex_direction: :'"double quotes"' }) }
		assert_equal output, %(<div style="flex-direction: &quot;double quotes&quot;;"></div>)
	end

	test ":style, Hash(Symbol, Phlex::SGML::SafeObject)" do
		output = phlex { div(style: { color: Phlex::SGML::SafeValue.new("blue") }) }
		assert_equal output, %(<div style="color: blue;"></div>)
	end

	test ":style, Hash(Symbol, nil)" do
		output = phlex { div(style: { color: nil }) }
		assert_equal output, %(<div style=""></div>)
	end

	test ":style, Hash(Symbol, *invalid*)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(style: { color: Object.new }) }
		end
	end

	test ":style, Hash(String, String)" do
		output = phlex { div(style: { "color" => "blue" }) }
		assert_equal output, %(<div style="color: blue;"></div>)
	end

	test ":style, Hash(*invalid*, String)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(style: { Object.new => "blue" }) }
		end
	end

	test ":srcset on img with an Array" do
		output = phlex { img(srcset: []) }
		assert_equal output, %(<img>)

		output = phlex { img(srcset: ["/width=400/image.jpg 1x", "/width=400,dpr=2/image.jpg 2x"]) }
		assert_equal output, %(<img srcset="/width=400/image.jpg 1x, /width=400%2Cdpr=2/image.jpg 2x">)

		output = phlex { img(srcset: ["/width=400/image.jpg 1x", ["/width=400,dpr=2/image.jpg 2x"]]) }
		assert_equal output, %(<img srcset="/width=400/image.jpg 1x, /width=400%2Cdpr=2/image.jpg 2x">)
	end

	test ":media on link with an Array" do
		output = phlex { link(media: []) }
		assert_equal output, %(<link>)

		output = phlex { link(media: ["screen", "print"]) }
		assert_equal output, %(<link media="screen, print">)

		output = phlex { link(media: ["(max-width: 600px)", "(min-width: 1200px)"]) }
		assert_equal output, %(<link media="(max-width: 600px), (min-width: 1200px)">)
	end

	test ":sizes on link with an Array" do
		output = phlex { link(sizes: []) }
		assert_equal output, %(<link>)

		output = phlex { link(sizes: ["16x16", "32x32", "64x64"]) }
		assert_equal output, %(<link sizes="16x16, 32x32, 64x64">)
	end

	test ":imagesrcset on link with an Array when rel is preload and as is image" do
		output = phlex { link(imagesrcset: [], rel: "preload", as: "image") }
		assert_equal output, %(<link rel="preload" as="image">)

		output = phlex { link(imagesrcset: ["image.jpg 1x", "image@2x.jpg 2x"], rel: "preload", as: "image") }
		assert_equal output, %(<link imagesrcset="image.jpg 1x, image@2x.jpg 2x" rel="preload" as="image">)

		output = phlex { link(imagesrcset: ["image.jpg 1x", "image@2x.jpg 2x"], rel: :preload, as: :image) }
		assert_equal output, %(<link imagesrcset="image.jpg 1x, image@2x.jpg 2x" rel="preload" as="image">)

		output = phlex { link(:imagesrcset => ["/width=400/image.jpg 1x", "/width=400,dpr=2/image@2x.jpg 2x"], "rel" => "preload", "as" => "image") }
		assert_equal output, %(<link imagesrcset="/width=400/image.jpg 1x, /width=400%2Cdpr=2/image@2x.jpg 2x" rel="preload" as="image">)
	end

	test ":accept on input with array when type is file" do
		output = phlex { input(accept: [], type: "file") }
		assert_equal output, %(<input type="file">)

		output = phlex { input(accept: ["image/jpeg", "image/png"], type: "file") }
		assert_equal output, %(<input accept="image/jpeg, image/png" type="file">)

		output = phlex { input(accept: ["image/jpeg", "image/png"], type: :file) }
		assert_equal output, %(<input accept="image/jpeg, image/png" type="file">)

		output = phlex { input(:accept => ["image/jpeg", "image/png"], "type" => "file") }
		assert_equal output, %(<input accept="image/jpeg, image/png" type="file">)
	end
end
