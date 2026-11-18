# frozen_string_literal: true

return unless defined?(Phlex::Native)

class NativeAttributesTest < Quickdraw::Test
	Attributes = Phlex::SGML::Attributes
	StringSubclass = Class.new(String)
	HashSubclass = Class.new(Hash)
	ArraySubclass = Class.new(Array)
	KELVIN_SIGN = [0x212A].pack("U")
	CAPITAL_I_WITH_DOT = [0x0130].pack("U")

	safe_object_string = +"javascript:alert(1)"
	safe_object_string.extend(Phlex::SGML::SafeObject)

	singleton_hash = { title: "x" }
	def singleton_hash.each = yield(:title, "y")

	cyclic_array = []
	cyclic_array << cyclic_array

	cyclic_hash = {}
	cyclic_hash[:_] = cyclic_hash

	KEYS = [
		:id,
		:class,
		:href,
		:src,
		:action,
		:formaction,
		:xlink_href,
		:data,
		:aria,
		:title,
		:type,
		:disabled,
		:style,
		:onclick,
		:srcdoc,
		:sandbox,
		:http_equiv,
		:foo_bar,
		:_,
		:on,
		:one,
		:"on-x",
		:BACKGROUND,
		:ID,
		:Id,
		:i_d,
		"id",
		"ID",
		"style",
		"data-x",
		"Href",
		"formAction",
		"x y",
		"a<b",
		"a\"b",
		"xlink:href",
		"",
		"_",
		"on_click",
		"é",
		"#{KELVIN_SIGN}ey",
		"#{CAPITAL_I_WITH_DOT}d",
		"\xff",
		"\xff".b,
		"a".encode("UTF-16LE"),
		"plain".encode("Shift_JIS"),
		"a" * 300,
		("b" * 300).to_sym,
		StringSubclass.new("title"),
		1,
		nil,
	].freeze

	SCALARS = [
		"",
		"a",
		"a b",
		"post_42",
		"/posts/1",
		"/search?q=ruby&page=2",
		"javascript:alert(1)",
		"JavaScript:x",
		"java&#115;cript:x",
		"jav&#x61;script:x",
		"javascr#{CAPITAL_I_WITH_DOT}pt:x",
		"&colon;",
		"say \"hi\"",
		"\"",
		"x\u0000y",
		"é",
		"\xff",
		"\xff".b,
		"\xff".dup.force_encoding("US-ASCII"),
		"é".encode("ISO-8859-1"),
		"a".encode("UTF-16LE"),
		"plain".encode("Shift_JIS"),
		"x" * 2000,
		"\"" * 100,
		:foo,
		:foo_bar,
		:"a\"b",
		:é_x,
		0,
		42,
		-7,
		2 ** 70,
		-(2 ** 70),
		1.5,
		-0.0,
		Float::INFINITY,
		Float::NAN,
		true,
		false,
		nil,
		Set[1, :a],
		Date.new(2020, 1, 1),
		Time.at(0).utc,
		Object.new,
		Phlex::SGML::SafeValue.new("s\"s"),
		Phlex::SGML::SafeValue.new("javascript:alert(1)"),
		Phlex::SGML::SafeValue.new("on_click_\xff"),
		Phlex::SGML::SafeValue.new(1),
		safe_object_string,
		StringSubclass.new("sub\"class"),
		HashSubclass[a: 1],
		ArraySubclass["a", "b"],
		singleton_hash,
		cyclic_array,
		cyclic_hash,
		[],
		{},
	].freeze

	def self.random_value(rng, depth)
		case rng.rand(10)
		when 0..5 then SCALARS.sample(random: rng)
		when 6, 7 then Array.new(rng.rand(5)) { (depth > 3) ? SCALARS.sample(random: rng) : random_value(rng, depth + 1) }
		else (depth > 3) ? "x" : random_hash(rng, depth + 1)
		end
	end

	def self.random_hash(rng, depth = 0)
		Array.new(rng.rand(5)) { [KEYS.sample(random: rng), random_value(rng, depth)] }.to_h
	end

	def self.outcome
		result = yield
		[:returned, result.b, result.encoding, result.frozen?]
	rescue Exception => e
		[:raised, e.class, e.message]
	end

	def self.compare(method_name, *args)
		ruby = outcome { Attributes.instance_method(method_name).bind_call(Attributes, *args) }
		native = outcome { Attributes.public_send(method_name, *args) }
		{ method_name:, args:, ruby:, native: } unless ruby == native
	end

	def self.compare_fetch(attributes)
		ruby = outcome { Attributes.instance_method(:generate_attributes).bind_call(Attributes, attributes) }
		native = outcome { Phlex::SERIALIZED_ATTRIBUTES.fetch(attributes) { Attributes.generate_attributes(attributes) } }
		{ method_name: :fetch, args: [attributes], ruby:, native: } unless ruby == native
	end

	test "is prepended to Phlex::SGML::Attributes" do
		assert_equal Attributes.singleton_class.ancestors.first, Phlex::Native::Attributes
	end

	test "replaces the attribute cache" do
		assert_equal Phlex::SERIALIZED_ATTRIBUTES, Phlex::Native::SerializedAttributes
	end

	test "fetch yields when it can't serialise the attributes" do
		assert_equal Phlex::SERIALIZED_ATTRIBUTES.fetch({ class: Set["a"] }) { "fallback" }, "fallback"
	end

	test "generate_attributes stays in Ruby so a fallback doesn't run the C twice" do
		assert_equal Attributes.method(:generate_attributes).owner, Attributes
	end

	test "matches the Ruby implementation on random attributes" do
		rng = Random.new(Integer(ENV.fetch("PHLEX_NATIVE_SEED", 0)))
		mismatches = []

		Integer(ENV.fetch("PHLEX_NATIVE_ITERATIONS", 20_000)).times do
			attributes = NativeAttributesTest.random_hash(rng)
			mismatches << NativeAttributesTest.compare_fetch(attributes)

			# The compiler only calls these with names that pass validation.
			attributes.each do |k, v|
				name = Attributes.attribute_name(k)
				Attributes.validate_attribute_name(k, name)
				method_name = Attributes.reference_attribute?(name) ? :reference_attribute : :attribute
				mismatches << NativeAttributesTest.compare(method_name, k, name, v)
				mismatches << NativeAttributesTest.compare(:attribute, k, name, v)
			rescue
				next
			end
		end

		mismatches.compact!
		assert_equal mismatches.first(3), []
	end

	test "matches the Ruby implementation on each key and value" do
		mismatches = []

		KEYS.each do |k|
			SCALARS.each do |v|
				mismatches << NativeAttributesTest.compare_fetch({ k => v })
				mismatches << NativeAttributesTest.compare_fetch({ data: { k => v } })
				mismatches << NativeAttributesTest.compare_fetch({ k => [v, "a", [v]] })
			end
		end

		mismatches.compact!
		assert_equal mismatches.first(3), []
	end
end
