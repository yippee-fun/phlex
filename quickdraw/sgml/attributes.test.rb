# frozen_string_literal: true

require "phlex"

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
