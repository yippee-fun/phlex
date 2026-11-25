# frozen_string_literal: true

require "attribute_generators"

# Renders generated attributes and parses them as a browser would, with
# Nokogiri's HTML5 parser, to check what a browser would see.
class AttributePropertiesTest < Quickdraw::Test
	include AttributeGenerators

	Attributes = Phlex::SGML::Attributes

	URL_ATTRIBUTES = Set["href", "src", "action", "formaction", "lowsrc", "dynsrc", "background", "ping", "xlink:href", "data"].freeze
	UNSAFE_ATTRIBUTES = Set["srcdoc", "sandbox", "http-equiv"].freeze
	EVENT_HANDLER = /\Aon[a-z]+\z/

	fuzz "renders attributes a browser reads as written, or refuses them", ATTRIBUTES do |attributes|
		# Safe values are trusted, so they skip the checks for unsafe names and URLs.
		output = Attributes.generate_attributes(attributes.reject { |_, v| trusted?(v) })
	rescue Phlex::ArgumentError
		nil
	else
		fragment = Nokogiri::HTML5.fragment("<div#{output}></div>")
		element = fragment.children.first

		assert_equal fragment.children.length, 1
		assert_equal element.name, "div"
		assert_equal element.children.length, 0

		element.attribute_nodes.each do |attribute|
			name = attribute.name
			refute_match name, EVENT_HANDLER
			refute UNSAFE_ATTRIBUTES.include?(name)
			refute javascript_url?(attribute.value) if URL_ATTRIBUTES.include?(name)
		end
	end

	fuzz "never renders a script URL", TEXT do |url|
		output = Attributes.generate_attributes({ :href => url, "src" => url })
		attributes = Nokogiri::HTML5.fragment("<a#{output}></a>").children.first.attribute_nodes

		attributes.each { |attribute| refute javascript_url?(attribute.value) }
		assert_equal attributes.length, 2 unless url.include?(":") || url.include?("&")
	end

	# An enclosing `noscript`, `textarea` or comment ends at the first `</noscript>`,
	# `</textarea>` or `-->`, even inside an attribute value, so no attribute can
	# contain an angle bracket. Safe values are escaped too.
	fuzz "never renders an angle bracket", ATTRIBUTES do |attributes|
		output = Attributes.generate_attributes(attributes)
	rescue Phlex::ArgumentError
		nil
	else
		refute output.include?("<")
		refute output.include?(">")
	end

	test "a string value renders with only its quotes and angle brackets escaped" do
		check(TEXT, NAME.filter { |name| name.match?(/\A[a-z]+(-[a-z]+)*\z/) && !name.start_with?("on") && !UNSAFE_ATTRIBUTES.include?(name) && !URL_ATTRIBUTES.include?(name) && name != "id" }) do |value, name|
			expected = %( #{name}="#{value.gsub(/["<>]/, '"' => '&quot;', '<' => '&lt;', '>' => '&gt;')}")

			assert_equal Attributes.generate_attributes({ name.to_sym => value }), expected
			assert_equal Attributes.generate_attributes({ name => value }), expected
			assert_equal Attributes.generate_attributes({ name.tr("-", "_").to_sym => value }), expected
		end
	end

	test "a string value renders the same whether its name is cached or not" do
		check(TEXT) do |value|
			assert_equal outcome { Attributes.generate_attributes({ title: value }) }, outcome { Attributes.generate_attributes({ "title" => value }) }
			assert_equal outcome { Attributes.generate_attributes({ href: value }) }, outcome { Attributes.generate_attributes({ "href" => value }) }
		end
	end

	private def trusted?(value)
		case value
		in Phlex::SGML::SafeValue then true
		in Hash then value.each_value.any? { |v| trusted?(v) }
		in Array | Set then value.any? { |v| trusted?(v) }
		else false
		end
	end

	private def outcome
		[:returned, yield]
	rescue => error
		[:raised, error.class, error.message]
	end

	# What a browser's URL parser does before reading the scheme: it strips
	# leading and trailing C0 controls and spaces, and removes tabs and newlines.
	private def javascript_url?(value)
		value.sub(/\A[\x00-\x20]+/, "").delete("\t\n\r").downcase(:ascii).start_with?("javascript:")
	end
end
