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
		assert_equal with_html, %(<div attribute="with &lt;html&gt;"></div>)

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
		assert_equal symbol_with_html, %(<div attribute="with &lt;html&gt;"></div>)

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

	test "_, Array(nil | token)" do
		output = phlex { div(class: [nil, "foo"]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [nil, :foo]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [nil, 42]) }
		assert_equal output, %(<div class="42"></div>)

		output = phlex { div(class: [nil, Phlex::SGML::SafeValue.new("foo")]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [nil, ["foo"]]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [nil, Set["foo"]]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [nil, nil, "foo", nil, "bar"]) }
		assert_equal output, %(<div class="foo bar"></div>)
	end

	test "_, Array(false | token)" do
		output = phlex { div(class: ["a", false]) }
		assert_equal output, %(<div class="a"></div>)

		output = phlex { div(class: [false, "a", [false, "b"], Set[false]]) }
		assert_equal output, %(<div class="a b"></div>)

		output = phlex { div(class: [false]) }
		assert_equal output, %(<div></div>)

		output = phlex { div(data: { action: ["a", false] }) }
		assert_equal output, %(<div data-action="a"></div>)
	end

	test "_, Array(true)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(class: ["a", true]) }
		end
	end

	test "_, Array(EmptyArray | String)" do
		output = phlex { div(class: [[], "foo"]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [Set[], "foo"]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [[nil, nil], "foo"]) }
		assert_equal output, %(<div class="foo"></div>)

		output = phlex { div(class: [[[], nil], ["foo"]]) }
		assert_equal output, %(<div class="foo"></div>)
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
		assert_equal with_html, %(<div data-controller="with &lt;html&gt;"></div>)

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
		assert_equal output, %(<div data-controller="with &lt;html&gt;"></div>)

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

	test "_, Hash(_, Date)" do
		output = phlex { div(data: { on: Date.new(2023, 1, 15) }) }
		assert_equal output, %(<div data-on="2023-01-15"></div>)
	end

	test "_, Hash(_, Time)" do
		output = phlex { div(data: { at: Time.new(2023, 1, 15, 12, 30, 45, "+00:00") }) }
		assert_equal output, %(<div data-at="2023-01-15T12:30:45+00:00"></div>)
	end

	test "_, Hash(_, Hash(_, Time))" do
		output = phlex { div(data: { event: { at: Time.new(2023, 1, 15, 12, 30, 45, "+02:00") } }) }
		assert_equal output, %(<div data-event-at="2023-01-15T12:30:45+02:00"></div>)
	end

	test "_, Hash(_, *responds to to_h*)" do
		output = phlex { div(data: { controller: Data.define(:hello).new(hello: "world") }) }
		assert_equal output, %(<div data-controller-hello="world"></div>)
	end

	test "_, Hash(_, *invalid*)" do
		assert_raises(Phlex::ArgumentError) do
			phlex { div(data: { controller: Object.new }) }
		end
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
		assert_equal output, %(<div></div>)
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

	test ":style, *responds to to_h*" do
		styles = Struct.new(:color, :font_weight, keyword_init: true).new(color: "blue", font_weight: "bold")

		output = phlex { div(style: styles) }
		assert_equal output, %(<div style="color: blue; font-weight: bold;"></div>)
	end

	test ":style, Array(Hash)" do
		output = phlex { div(style: [{ color: "blue" }, { font_weight: "bold", line_height: 1.5 }]) }
		assert_equal output, %(<div style="color: blue; font-weight: bold; line-height: 1.5;"></div>)
	end

	test ":style, Array with empty entries" do
		output = phlex { div(style: ["color: red", {}, "", { top: nil }, "x: y"]) }
		assert_equal output, %(<div style="color: red; x: y;"></div>)

		output = phlex { div(style: []) }
		assert_equal output, %(<div></div>)

		output = phlex { div(style: ["", {}, { color: nil }]) }
		assert_equal output, %(<div></div>)
	end

	test ":style, Array(false)" do
		output = phlex { div(style: ["color: red", false]) }
		assert_equal output, %(<div style="color: red;"></div>)

		output = phlex { div(style: Set[false]) }
		assert_equal output, %(<div></div>)

		assert_raises(Phlex::ArgumentError) do
			phlex { div(style: ["color: red", true]) }
		end
	end

	test ":style, Hash(_, false)" do
		output = phlex { div(style: { color: false, top: 0 }) }
		assert_equal output, %(<div style="top: 0;"></div>)

		output = phlex { div(style: { color: false }) }
		assert_equal output, %(<div></div>)

		assert_raises(Phlex::ArgumentError) do
			phlex { div(style: { color: true }) }
		end
	end

	test ":style, Set(nil)" do
		output = phlex { div(style: Set[nil]) }
		assert_equal output, %(<div></div>)
	end

	test ":style, Set(String)" do
		output = phlex { div(style: Set["color: blue"]) }
		assert_equal output, %(<div style="color: blue;"></div>)
	end

	test ":style, Hash(Symbol, String)" do
		output = phlex { div(style: { color: "blue", font_weight: "bold" }) }
		assert_equal output, %(<div style="color: blue; font-weight: bold;"></div>)
	end

	test ":style, Hash with nil values" do
		output = phlex { div(style: { top: nil, color: "blue", left: nil, font_weight: "bold" }) }
		assert_equal output, %(<div style="color: blue; font-weight: bold;"></div>)

		output = phlex { div(style: { color: nil }) }
		assert_equal output, %(<div></div>)

		output = phlex { div(style: {}) }
		assert_equal output, %(<div></div>)
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
		assert_equal output, %(<div></div>)
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

		output = phlex { img(srcset: [nil, "a.png 1x"]) }
		assert_equal output, %(<img srcset="a.png 1x">)

		output = phlex { img(srcset: [[], nil, "a.png 1x", nil, "b.png 2x"]) }
		assert_equal output, %(<img srcset="a.png 1x, b.png 2x">)
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

	test "a reference attribute is checked every time, even once its name is cached" do
		assert_equal phlex { a(href: "/a") }, %(<a href="/a"></a>)
		assert_equal phlex { a(href: "javascript:alert(1)") }, %(<a></a>)
		assert_equal phlex { a("Href" => "/a") }, %(<a Href="/a"></a>)
		assert_equal phlex { a("Href" => "javascript:alert(1)") }, %(<a></a>)
	end

	test "a safe reference is kept once its name is cached" do
		Phlex::SGML::Attributes.generate_attributes({ href: "/a" })
		assert_equal Phlex::SGML::Attributes.generate_attributes({ href: Phlex::SGML::SafeValue.new("javascript:trusted()") }), %( href="javascript:trusted()")

		# Another safe object, such as an html_safe string, is still checked.
		safe_string = +"javascript:trusted()"
		safe_string.extend(Phlex::SGML::SafeObject)
		assert_equal Phlex::SGML::Attributes.generate_attributes({ href: safe_string }), ""
	end

	test "a URL that isn't a script URL is kept, even with a j, a colon or a character reference" do
		assert_equal phlex { a(href: "https://example.com/jobs") }, %(<a href="https://example.com/jobs"></a>)
		assert_equal phlex { a(href: "https://example.com/?a=1&amp;b=Jam") }, %(<a href="https://example.com/?a=1&amp;b=Jam"></a>)
		refute Phlex::SGML::Attributes.unsafe_reference?("https://example.com/jobs")
		refute Phlex::SGML::Attributes.unsafe_reference?("mailto:jo@example.com?subject=a&amp;b")
	end

	test "a String subclass can't hide a script URL by overriding downcase" do
		sneaky = Class.new(String) { def downcase(*) = "https://example.com" }

		assert_equal phlex { a(href: sneaky.new("javascript:alert('sneaky')")) }, %(<a></a>)
	end

	test "checked names are cached up to a limit, in shareable hashes" do
		Phlex::SGML::Attributes.generate_attributes({ title: "a", href: "/a" })
		checked_names = Phlex::SGML::Attributes.instance_variable_get(:@checked_names)
		checked_reference_names = Phlex::SGML::Attributes.instance_variable_get(:@checked_reference_names)

		assert_equal checked_names[:title], "title"
		assert_equal checked_reference_names[:href], "href"
		refute checked_names.key?(:href)
		assert Ractor.shareable?(checked_names) if defined?(Ractor)

		defer { Phlex::SGML::Attributes.instance_variable_set(:@checked_names, checked_names) }
		names = ("aaaa".."zzzz").first(Phlex::SGML::Attributes::CHECKED_NAMES_LIMIT + 1)
		Phlex::SGML::Attributes.generate_attributes(names.to_h { |name| [:"data-#{name}", "x"] })

		assert_equal Phlex::SGML::Attributes.instance_variable_get(:@checked_names).size, Phlex::SGML::Attributes::CHECKED_NAMES_LIMIT
	end

	test "names that start with on but aren't event handlers" do
		assert_equal phlex { div(:on => "x", "on-x" => "y") }, %(<div on="x" on-x="y"></div>)
		assert_raises(Phlex::ArgumentError) { phlex { div(onx: "x") } }
	end

	test "validate_attribute_name refuses what serialising refuses" do
		["onclick", "ONCLICK", "on:click", "srcdoc", "x y", "a\"b"].each do |name|
			assert_raises(Phlex::ArgumentError) { Phlex::SGML::Attributes.validate_attribute_name(name, name) }
		end

		error = assert_raises(Phlex::ArgumentError) { Phlex::SGML::Attributes.validate_attribute_name("ID", "ID") }
		assert_equal error.message, ":id attribute should only be passed as a lowercase symbol."

		assert_equal Phlex::SGML::Attributes.validate_attribute_name(:title, "title"), nil
	end

	test "reference_attribute? normalises the name" do
		assert Phlex::SGML::Attributes.reference_attribute?("HREF")
		assert Phlex::SGML::Attributes.reference_attribute?("xlink:href")
		refute Phlex::SGML::Attributes.reference_attribute?("title")
	end

	test "quotes are escaped in every kind of value" do
		output = phlex do
			div(
				title: Phlex::SGML::SafeValue.new(%(a"b)),
				data: { a: %(x"y), b: :"x\"y", c: Phlex::SGML::SafeValue.new(%(s"s)) },
				style: Set[%(content: "x")],
			)
		end

		assert_equal output, %(<div title="a&quot;b" data-a="x&quot;y" data-b="x&quot;y" data-c="s&quot;s" style="content: &quot;x&quot;;"></div>)
	end

	test "nested dates and times" do
		output = phlex { div(data: { day: Date.new(2020, 1, 2), at: Time.new(2020, 1, 2, 3, 4, 5, "+00:00") }) }
		assert_equal output, %(<div data-day="2020-01-02" data-at="2020-01-02T03:04:05+00:00"></div>)
	end

	test "nested sets of tokens" do
		assert_equal phlex { div(class: ["x", Set["a", "b"]]) }, %(<div class="x a b"></div>)
		assert_equal phlex { img(srcset: ["a.jpg 1x", Set["/w=1,2/b.jpg 2x"]]) }, %(<img srcset="a.jpg 1x, /w=1%2C2/b.jpg 2x">)
	end

	test "invalid values raise with a message" do
		{
			-> { div(title: Object.new) } => /\AInvalid attribute value for title: #<Object/,
			-> { div(data: { 1 => "x" }) } => /\AAttribute keys should be Strings or Symbols/,
			-> { div(data: { "a b" => "x" }) } => /\AUnsafe attribute name detected: a b\.\z/,
			-> { div(data: { a: Object.new }) } => /\AInvalid attribute value #<Object/,
			-> { div(class: [Object.new]) } => /\AInvalid token type: Object\.\z/,
			-> { div(style: [1]) } => /\AInvalid style: 1\.\z/,
			-> { div(style: { 1 => "x" }) } => /\AStyle keys should be Strings or Symbols\.\z/,
			-> { div(style: { a: [1] }) } => /\AInvalid style value: \[1\]\z/,
		}.each do |block, message|
			error = assert_raises(Phlex::ArgumentError) { phlex(&block) }
			assert_match error.message, message
		end
	end

	test "a character reference to an invalid code point in a URL decodes as a replacement character" do
		assert_equal phlex { a(href: "/?q=&#xD800;") }, %(<a href="/?q=&#xD800;"></a>)
		assert_equal phlex { a(href: "/?q=&#x110000;&#99999999999999999999;") }, %(<a href="/?q=&#x110000;&#99999999999999999999;"></a>)
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#xD7FF;&#xD800;&#xDFFF;&#xE000;"), "퟿��"
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#1114111;&#1114112;&#x6A;"), "\u{10FFFF}�j"
	end

	test "a nested hash can't make an unsafe attribute name" do
		[
			{ http: { equiv: "refresh" } },
			{ "HTTP" => { "Equiv" => "refresh" } },
			{ http: { "eq:uiv" => "refresh" } },
			{ http: { "equİv" => "refresh" } },
			{ http: { equiv: { _: "refresh" } } },
		].each do |attributes|
			error = assert_raises(Phlex::ArgumentError) { phlex { meta(**attributes) } }
			assert_match error.message, /\AUnsafe attribute name detected: http-/i
		end

		assert_equal phlex { meta(http: { equiv: Phlex::SGML::SafeValue.new("refresh") }) }, %(<meta http-equiv="refresh">)
		assert_equal phlex { meta(http: { equiv: { _: Phlex::SGML::SafeValue.new("refresh") } }) }, %(<meta http-equiv="refresh">)
		assert_equal phlex { meta(http: { equiv: { mode: "local" } }) }, %(<meta http-equiv-mode="local">)
		assert_equal phlex { meta(data: { http: { equiv: "x" } }) }, %(<meta data-http-equiv="x">)
	end

	test "an empty attribute name is refused" do
		["", :""].each do |name|
			[true, "x", { a: "b" }].each do |value|
				error = assert_raises(Phlex::ArgumentError) { phlex { div(name => value) } }
				assert_equal error.message, "Attribute names can't be empty."
			end
		end

		assert_equal phlex { div(data: { "" => "x" }) }, %(<div data-="x"></div>)
	end

	test "attributes render in the order given, whatever was rendered before" do
		component = Class.new(Phlex::HTML) do
			def initialize(style) = @style = style
			def view_template = div(**@style)
		end

		component.new({ style: { margin: 0, margin_top: "1px" } }).call
		assert_equal component.new({ style: { margin_top: "1px", margin: 0 } }).call, %(<div style="margin-top: 1px; margin: 0;"></div>)
	end

	test "attribute values can't end an enclosing noscript" do
		output = phlex { noscript { img(alt: "</noscript><img src=x onerror=alert(1)>") } }
		assert_equal output, %(<noscript><img alt="&lt;/noscript&gt;&lt;img src=x onerror=alert(1)&gt;"></noscript>)
	end

	test "attribute values can't end an enclosing comment" do
		output = phlex { comment { span(title: "--><img src=x onerror=alert(1)>") } }
		assert_equal output, %(<!-- <span title="--&gt;&lt;img src=x onerror=alert(1)&gt;"></span> -->)
	end

	test "angle brackets are escaped in every kind of attribute value" do
		assert_equal phlex { div(title: :"<x>") }, %(<div title="&lt;x&gt;"></div>)
		assert_equal phlex { div(class: ["<a>", :"<b>"]) }, %(<div class="&lt;a&gt; &lt;b&gt;"></div>)
		assert_equal phlex { div(data: { x: "<y>" }) }, %(<div data-x="&lt;y&gt;"></div>)
		assert_equal phlex { div(style: { content: "'<x>'" }) }, %(<div style="content: '&lt;x&gt;';"></div>)
		assert_equal phlex { div(style: ["content: '<x>'"]) }, %(<div style="content: '&lt;x&gt;';"></div>)
		assert_equal phlex { div(title: safe("<x>")) }, %(<div title="&lt;x&gt;"></div>)
		assert_equal phlex { a(href: "/search?q=<x>") }, %(<a href="/search?q=&lt;x&gt;"></a>)
	end

	test "SVG animation values that are script URLs are dropped" do
		svg = -> (&block) { Class.new(Phlex::SVG) { define_method(:view_template, &block) }.call }

		assert_equal svg.() { set(attributeName: "href", to: "javascript:alert(1)") }, %(<set attributeName="href"></set>)
		assert_equal svg.() { animate(attributeName: "href", from: "javascript:alert(1)", to: "#a") }, %(<animate attributeName="href" to="#a"></animate>)
		assert_equal svg.() { animate(attributeName: "href", by: "javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: "javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { set(attributeName: "href", to: "JavaScript&colon;alert(1)") }, %(<set attributeName="href"></set>)
		assert_equal svg.() { set("attributename" => "href", "TO" => "javascript:alert(1)") }, %(<set attributename="href"></set>)
	end

	test "every entry of an SVG animation's values is checked" do
		svg = -> (&block) { Class.new(Phlex::SVG) { define_method(:view_template, &block) }.call }

		assert_equal svg.() { animate(attributeName: "href", values: "#a;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: "#a; javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: "#a&#59;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: "#a&semi;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: ["#a;", "javascript:alert(1)"]) }, %(<animate attributeName="href"></animate>)
		assert_equal svg.() { animate(attributeName: "x", values: "0;10;0") }, %(<animate attributeName="x" values="0;10;0"></animate>)
		assert_equal svg.() { animate(attributeName: "href", values: "#a;#b") }, %(<animate attributeName="href" values="#a;#b"></animate>)
	end

	test "values lists are checked entry by entry however they're serialised" do
		assert Phlex::SGML::Attributes.reference_attribute?("values")
		assert Phlex::SGML::Attributes.reference_list_attribute?("VALUES")
		refute Phlex::SGML::Attributes.reference_list_attribute?("href")
		assert_equal Phlex::SGML::Attributes.reference_attribute(:values, "values", "#a;javascript:alert(1)"), ""
		assert_equal Phlex::SGML::Attributes.reference_attribute(:to, "to", "javascript:alert(1)"), ""
		assert_equal Phlex::SGML::Attributes.reference_attribute(:values, "values", "#a;#b"), %( values="#a;#b")

		# The first render remembers names it has checked; lists are never remembered.
		2.times { assert_equal Phlex::SGML::Attributes.generate_attributes({ values: "#a;javascript:alert(1)" }), "" }
	end

	test "only safe values skip the checks for unsafe names and script URLs" do
		# Like Rails' html_safe strings, which phlex-rails makes safe objects.
		html_safe = Class.new(String) { include Phlex::SGML::SafeObject }
		safe_object = Class.new { include Phlex::SGML::SafeObject; def to_s = "alert(1)" }

		assert_equal phlex { a(href: html_safe.new("javascript:alert(1)")) }, %(<a></a>)
		assert_equal phlex { a("href" => html_safe.new("javascript:alert(1)")) }, %(<a></a>)
		assert_equal Phlex::SGML::Attributes.reference_attribute(:href, "href", html_safe.new("javascript:alert(1)")), ""
		assert_raises(Phlex::ArgumentError) { phlex { div(onclick: html_safe.new("alert(1)")) } }
		assert_raises(Phlex::ArgumentError) { phlex { div(onclick: safe_object.new) } }
		assert_raises(Phlex::ArgumentError) { phlex { iframe(srcdoc: html_safe.new("<script></script>")) } }
		assert_raises(Phlex::ArgumentError) { phlex { meta(http: { equiv: safe_object.new }) } }

		assert_equal phlex { a(href: safe("javascript:alert(1)")) }, %(<a href="javascript:alert(1)"></a>)
		assert_equal phlex { div(onclick: safe("alert(1)")) }, %(<div onclick="alert(1)"></div>)
		assert_equal phlex { meta(http: { equiv: safe("refresh") }) }, %(<meta http-equiv="refresh">)
	end

	test "a values list can't hide an entry behind a reference the decoder removes" do
		svg = -> (&block) { Class.new(Phlex::SVG) { define_method(:view_template, &block) }.call }

		# Browsers keep references they don't know, and case matters to them.
		["#a&zz;javascript:alert(1)", "#a&TAB;javascript:alert(1)", "#a&ampx;javascript:alert(1)", "#a&#38;zz;javascript:alert(1)"].each do |values|
			assert_equal svg.() { animate(attributeName: "href", values:) }, %(<animate attributeName="href"></animate>)
		end

		assert_equal svg.() { animate(attributeName: "x", values: "0;10&amp;;0") }, %(<animate attributeName="x" values="0;10&amp;;0"></animate>)
	end

	test "a namespaced name is a reference if its local name is one" do
		svg = -> (&block) { Class.new(Phlex::SVG) { define_method(:view_template, &block) }.call }

		assert_equal svg.() { a("xmlns:x": "http://www.w3.org/1999/xlink", "x:href": "javascript:alert(1)") }, %(<a xmlns:x="http://www.w3.org/1999/xlink"></a>)
		assert_equal svg.() { a("X:HREF" => "javascript:alert(1)") }, %(<a></a>)
		assert_equal svg.() { set("x:to": "javascript:alert(1)") }, %(<set></set>)
		assert_equal svg.() { animate("x:values": "#a;javascript:alert(1)") }, %(<animate></animate>)
		assert_equal svg.() { a("x:href": "#a") }, %(<a x:href="#a"></a>)
		assert Phlex::SGML::Attributes.reference_attribute?("x:href")
		assert Phlex::SGML::Attributes.reference_list_attribute?("x:values")
		assert_equal Phlex::SGML::Attributes.reference_attribute(:"x:values", "x:values", "#a;javascript:alert(1)"), ""
	end

	test "a nested name can't be a namespaced reference" do
		assert_raises(Phlex::ArgumentError) { phlex { a(x: { "a:href" => "/a" }) } }
		assert_raises(Phlex::ArgumentError) { phlex { a(data: { "very-long-nested-prefix:href" => "/a" }) } }
		assert_equal phlex { div(data: { "a:b" => "c" }) }, %(<div data-a:b="c"></div>)
	end

	test "a nested root key's name is checked however it's serialised" do
		assert_raises(Phlex::ArgumentError) { Phlex::SGML::Attributes.attribute(:"http-equiv", "http-equiv", { _: "refresh" }) }
		assert_raises(Phlex::ArgumentError) { Phlex::SGML::Attributes.reference_attribute(:"http-equiv", "http-equiv", { _: "refresh" }) }
	end

	test "numeric references with very many digits decode as U+FFFD without parsing them" do
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&##{'9' * 100_000};"), "\uFFFD"
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#x#{'f' * 100_000};"), "\uFFFD"
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&##{'0' * 100_000}106;"), "j"
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#x#{'0' * 100_000}6a;"), "j"
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#1114111;"), 1114111.chr(Encoding::UTF_8)
		assert_equal Phlex::SGML::Attributes.decode_html_character_references("&#11141110;"), "\uFFFD"
		assert_equal phlex { a(href: "&##{'0' * 50}106;avascript:alert(1)") }, %(<a></a>)
	end

	test "a reference is checked without asking the value whether it's true" do
		value = Class.new(String) { def ==(_other) = raise("asked") }.new("/x")

		# String keys are never remembered as checked, so they take the full path.
		assert_equal Phlex::SGML::Attributes.generate_attributes({ "href" => value }), %( href="/x")
		assert_equal Phlex::SGML::Attributes.reference_attribute(:href, "href", value), %( href="/x")
	end

	test "a URL attribute can't take its value from a nested root key" do
		[{ _: "javascript:alert(1)" }, { _: { _: "javascript:alert(1)" } }, { _: ["javascript:alert(1)"] }, Class.new { def to_h = { _: "javascript:alert(1)" } }.new].each do |value|
			assert_raises(Phlex::ArgumentError) { phlex { iframe(src: value) } }
			assert_raises(Phlex::ArgumentError) { phlex { a(href: value) } }
			assert_raises(Phlex::ArgumentError) { Class.new(Phlex::SVG) { define_method(:view_template) { set(attributeName: "href", to: value) } }.call }
		end

		# Rescued, nothing of the value is left behind.
		component = Class.new(Phlex::HTML) { define_method(:view_template) { begin; iframe(src: { _: "javascript:alert(1)" }); rescue Phlex::ArgumentError; nil; end } }
		refute component.call.include?("javascript")
	end

	test "data is checked as a URL unless it's a Hash of data attributes" do
		assert_equal phlex { object(data: "javascript:alert(1)") }, %(<object></object>)
		assert_equal phlex { object(data: :"javascript:alert(1)") }, %(<object></object>)
		assert_equal phlex { object(data: ["javascript:alert(1)"]) }, %(<object></object>)
		assert_equal phlex { object("data" => "javascript:alert(1)") }, %(<object></object>)
		assert_equal phlex { object(DATA: "JavaScript&colon;alert(1)") }, %(<object></object>)
		assert_equal Phlex::SGML::Attributes.reference_attribute(:data, "data", "javascript:alert(1)"), ""

		# Remembered names are checked too.
		2.times { assert_equal phlex { object(data: "javascript:alert(1)") }, %(<object></object>) }

		assert_equal phlex { object(data: "/files/report.pdf", type: "application/pdf") }, %(<object data="/files/report.pdf" type="application/pdf"></object>)
		assert_equal phlex { div(data: { controller: "x", action: "javascript:y" }) }, %(<div data-controller="x" data-action="javascript:y"></div>)
		assert_equal phlex { div(data: []) }, %(<div></div>)
		assert_equal Phlex::SGML::Attributes.reference_attribute(:data, "data", { controller: "x" }), %( data-controller="x")
		assert_equal phlex { object(data: safe("javascript:alert(1)")) }, %(<object data="javascript:alert(1)"></object>)
	end
end
