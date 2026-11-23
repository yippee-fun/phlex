# frozen_string_literal: true

require "phlex"
require "uri"

def phlex(component = Phlex::HTML, *args, **kwargs, &block)
	component.new(*args, **kwargs).call do |element|
		element.instance_exec(&block)
	end
end

test "unsafe href attribute with encoded character references" do
	[
		phlex { a(href: "java&#x73;cript:alert(1)") },
		phlex { a(href: "javascript&#58;alert(1)") },
		phlex { a(href: "java&#115;cript:alert(1)") },
		phlex { a(href: "&#106;avascript:alert(1)") },
		phlex { a(href: "javascript&#58alert(1)") },
		phlex { a(href: "javascript&colon;alert(1)") },
	].each do |output|
		assert_equal_html output, %(<a></a>)
	end
end

test "unsafe xlink:href attribute" do
	[
		phlex(Phlex::SVG) { a("xlink:href": "javascript:alert(1)") { "x" } },
		phlex(Phlex::SVG) { a("xlink:href": "javascript&colon;alert(1)") { "x" } },
		phlex(Phlex::SVG) { a("xlink:href": "javascript&#58alert(1)") { "x" } },
	].each do |output|
		assert_equal_html output, %(<a>x</a>)
	end
end

test "unsafe attribute name with space (String)" do
	error = assert_raises(ArgumentError) do
		phlex { div("foo bar" => true) }
	end

	assert_equal error.message, "Unsafe attribute name detected: foo bar."
end

test "unsafe attribute name with space (Symbol)" do
	error = assert_raises(ArgumentError) do
		phlex { div("foo bar": true) }
	end

	assert_equal error.message, "Unsafe attribute name detected: foo bar."
end

test "unsafe attribute name with slash (String)" do
	error = assert_raises(ArgumentError) do
		phlex { div("foo/bar" => true) }
	end

	assert_equal error.message, "Unsafe attribute name detected: foo/bar."
end

test "unsafe attribute name with slash (Symbol)" do
	error = assert_raises(ArgumentError) do
		phlex { div("foo/bar": true) }
	end

	assert_equal error.message, "Unsafe attribute name detected: foo/bar."
end

test "SVG animation values that are script URLs are dropped" do
	[
		[phlex(Phlex::SVG) { set(attributeName: "href", to: "javascript:alert(1)") }, %(<set attributeName="href"></set>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", from: "javascript:alert(1)", to: "#a") }, %(<animate attributeName="href" to="#a"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", by: "javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { set(attributeName: "href", to: "JavaScript&colon;alert(1)") }, %(<set attributeName="href"></set>)],
		[phlex(Phlex::SVG) { set(attributeName: "href", to: :"javascript:alert(1)") }, %(<set attributeName="href"></set>)],
		[phlex(Phlex::SVG) { set("attributename" => "href", "TO" => "javascript:alert(1)") }, %(<set attributename="href"></set>)],
	].each do |output, expected|
		assert_equal_html output, expected
	end
end

test "every entry of an SVG animation's values is checked" do
	[
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "#a;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "#a; javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "#a&#59;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "#a&semi;javascript:alert(1)") }, %(<animate attributeName="href"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "x", values: "0;10;0") }, %(<animate attributeName="x" values="0;10;0"></animate>)],
		[phlex(Phlex::SVG) { animate(attributeName: "href", values: "#a;#b") }, %(<animate attributeName="href" values="#a;#b"></animate>)],
		[phlex(Phlex::SVG) { set(attributeName: "x", to: "10") }, %(<set attributeName="x" to="10"></set>)],
	].each do |output, expected|
		assert_equal_html output, expected
	end
end

test "event attributes outside the old list are unsafe" do
	[
		-> { phlex(Phlex::SVG) { set(attributeName: "x", to: "1", onbegin: "alert(1)") } },
		-> { phlex { div(onanimationstart: "alert(1)") } },
		-> { phlex { div(onpointerover: "alert(1)") } },
		-> { phlex { div("OnBegin" => "alert(1)") } },
		-> { phlex { div("onfocusin" => "alert(1)") } },
	].each do |render|
		error = assert_raises(ArgumentError) { render.call }
		assert error.message.start_with?("Unsafe attribute name detected:")
	end
end

test "attributes that start with on- or are nested aren't event attributes" do
	assert_equal_html phlex { div("on-click": "x") }, %(<div on-click="x"></div>)
	assert_equal_html phlex { div(data: { on_click: "x" }) }, %(<div data-on-click="x"></div>)
	assert_equal_html phlex { div(data_on: "x") }, %(<div data-on="x"></div>)
	assert_equal_html phlex { div(on: "x") }, %(<div on="x"></div>)
	assert_equal_html phlex { div(on_begin: "x") }, %(<div on-begin="x"></div>)
end

test "references are checked whatever type their value is" do
	assert_equal_html phlex { a(href: ["javascript:alert(1)"]) }, %(<a></a>)
	assert_equal_html phlex { a(href: Set["javascript:alert(1)"]) }, %(<a></a>)
	assert_equal_html phlex { a(href: URI("javascript:alert(1)")) }, %(<a></a>)
	assert_equal_html phlex { a(href: Class.new { def to_str = "javascript:alert(1)" }.new) }, %(<a></a>)
	assert_equal_html phlex { a(href: Class.new { def to_phlex_attribute_value = "javascript:alert(1)" }.new) }, %(<a></a>)
	assert_equal_html phlex { a(href: URI("https://example.com/")) }, %(<a href="https://example.com/"></a>)
	assert_equal_html phlex { a(href: ["/a", "/b"]) }, %(<a href="/a /b"></a>)
	assert_equal_html phlex { a(href: 1) }, %(<a href="1"></a>)
end

test "a values list can't hide an entry behind a reference the decoder removes" do
	# Browsers keep references they don't know, and case matters to them.
	["#a&zz;javascript:alert(1)", "#a&TAB;javascript:alert(1)", "#a&ampx;javascript:alert(1)", "#a&#38;zz;javascript:alert(1)"].each do |values|
		assert_equal_html phlex(Phlex::SVG) { animate(attributeName: "href", values: values) }, %(<animate attributeName="href"></animate>)
	end
end

test "data is checked as a URL unless it's a Hash of data attributes" do
	assert_equal_html phlex { object(data: "javascript:alert(1)") }, %(<object></object>)
	assert_equal_html phlex { object(data: :"javascript:alert(1)") }, %(<object></object>)
	assert_equal_html phlex { object(data: ["javascript:alert(1)"]) }, %(<object></object>)
	assert_equal_html phlex { object("data" => "javascript:alert(1)") }, %(<object></object>)
	assert_equal_html phlex { object(data: URI("javascript:alert(1)")) }, %(<object></object>)
	assert_equal_html phlex { object(data: "/files/report.pdf") }, %(<object data="/files/report.pdf"></object>)
	assert_equal_html phlex { div(data: { controller: "x" }) }, %(<div data-controller="x"></div>)
end
