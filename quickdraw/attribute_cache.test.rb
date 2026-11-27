# frozen_string_literal: true

require "attribute_generators"

class AttributeCacheTest < Quickdraw::Test
	Cache = Phlex::AttributeCache
	SafeString = Class.new(String) { include Phlex::SGML::SafeObject }

	def setup
		@cache = Cache.new
	end

	private def fetch(attributes) = @cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }

	private def safe_string(value) = (+value).extend(Phlex::SGML::SafeObject)

	test "hits with an equal hash of plain values" do
		attributes = { id: "a", class: ["b", :c, nil], data: { d: 1, e: true, f: false }, title: Phlex::SGML::SafeValue.new("t") }
		fetch(attributes)

		assert_equal @cache.fetch(Marshal.load(Marshal.dump(attributes))) { raise }, fetch(attributes)
		assert_equal @cache.size, 1
	end

	test "misses when the pairs are in another order" do
		fetch({ style: { margin: 0, margin_top: "1px" } })

		assert_equal fetch({ style: { margin_top: "1px", margin: 0 } }), %( style="margin-top: 1px; margin: 0;")
		assert_equal fetch({ "title" => "b", :title => "a" }), %( title="b" title="a")
	end

	test "misses when a value is safe, or a subclass, but the cached one isn't" do
		fetch({ id: "a", href: "javascript:x()" })

		assert_equal fetch({ id: "a", href: Phlex::SGML::SafeValue.new("javascript:x()") }), %( id="a" href="javascript:x()")
		# Only Phlex's own safe values skip the script URL check.
		assert_equal fetch({ id: "a", href: safe_string("javascript:x()") }), %( id="a")
		assert_equal fetch({ id: "a", href: SafeString.new("javascript:x()") }), %( id="a")
		assert_equal fetch({ id: "a", href: Class.new(String).new("javascript:x()") }), %( id="a")
	end

	test "never answers for a plain string with a safe one's output" do
		fetch({ id: "a", onclick: Phlex::SGML::SafeValue.new("x()") })

		assert_raises(Phlex::ArgumentError) { fetch({ id: "a", onclick: "x()" }) }
		assert_raises(Phlex::ArgumentError) { fetch({ id: "a", onclick: safe_string("x()") }) }
	end

	test "misses when a string has another encoding" do
		fetch({ title: "a" })

		assert_equal @cache[{ title: "a".b }], nil
	end

	test "doesn't cache values whose output eql? can't tell apart" do
		[
			{ data: { x: 0.0 } },
			{ data: { at: Time.utc(2020) } },
			{ class: Set["a"] },
			{ title: safe_string("x") },
			{ title: SafeString.new("x") },
			{ title: Phlex::SGML::SafeValue.new(SafeString.new("x")) },
			{ data: Class.new(Hash)[x: 1] },
			{ class: Class.new(Array)["a"] },
		].each { |attributes| fetch(attributes) }

		assert_equal @cache.size, 0
		assert_equal fetch({ data: { x: -0.0 } }), %( data-x="-0.0")
		assert_equal fetch({ data: { at: Time.new(2020, 1, 1, 1, 0, 0, "+01:00") } }), %( data-at="2020-01-01T01:00:00+01:00")
	end

	test "is unaffected by changes to the hash it cached" do
		data = { x: +"1" }
		fetch({ data: })
		data[:x] << "2"

		assert_equal fetch({ data: { x: "1" } }), %( data-x="1")
		assert_equal fetch({ data: }), %( data-x="12")
	end

	test "a different hash with the same digest doesn't hit" do
		[
			[{ a: 1, b: 2 }, { a: 1 }],
			[{ a: 1 }, { a: 1, b: 2 }],
			[{ a: 1 }, { b: 1 }],
			[{ a: 1 }, { "a" => 1 }],
			[{ a: [1, 2] }, { a: [1] }],
			[{ a: [1] }, { a: [1, 2] }],
			[{ a: [1, 2] }, { a: [1, 3] }],
			[{ a: [1, 2] }, { a: [3, 2] }],
			[{ a: [1] }, { a: Class.new(Array)[1] }],
			[{ a: { b: 1 } }, { a: Class.new(Hash)[b: 1] }],
			[{ a: 1 }, Class.new(Hash)[a: 1]],
			[{ a: [1] }, { a: { b: 1 } }],
			[{ a: { b: 1 } }, { a: [1] }],
			[{ a: "x" }, { a: "y" }],
			[{ a: "x" }, { a: :x }],
			[{ a: :x }, { a: "x" }],
			[{ a: 1 }, { a: 1.0 }],
			[{ a: Phlex::SGML::SafeValue.new("x") }, { a: Phlex::SGML::SafeValue.new("y") }],
			[{ a: Phlex::SGML::SafeValue.new("x") }, { a: "x" }],
			[{ a: "x" }, { a: Phlex::SGML::SafeValue.new("x") }],
			[{ a: Phlex::SGML::SafeValue.new("x") }, { a: Phlex::SGML::SafeValue.new(SafeString.new("x")) }],
			[{ a: Phlex::SGML::SafeValue.new("x") }, { a: Phlex::SGML::SafeValue.new("x".b) }],
		].each do |cached, given|
			cache = Cache.new
			cache.__send__(:store, given.hash, cache.__send__(:snapshot, cached, [Float::INFINITY]), "cached")

			assert_equal cache[given], nil
			assert_equal cache.fetch(given) { "generated" }, "generated"
		end
	end

	fuzz "renders what serialising renders, whatever was cached before", AttributeGenerators::ATTRIBUTES do |attributes|
		[attributes, reversed(attributes), Marshal.load(Marshal.dump(attributes))].each do |variant|
			assert_equal outcome { fetch(variant) }, outcome { Phlex::SGML::Attributes.generate_attributes(variant) }
		end
	end

	private def reversed(value)
		case value
		when Hash then value.to_a.reverse.to_h { |k, v| [k, reversed(v)] }
		when Array then value.reverse.map { |item| reversed(item) }
		else value
		end
	end

	private def outcome
		[:returned, yield]
	rescue => error
		[:raised, error.class, error.message.gsub(/0x\h+/, "0x")]
	end

	test "doesn't snapshot keys of skipped pairs, or output too empty or large to keep" do
		cyclic = []
		cyclic << cyclic

		assert_equal fetch({ :id => "a", cyclic => nil }), %( id="a")
		assert_equal fetch({ :id => "b", 1 => false }), %( id="b")
		assert_equal fetch({ title: nil }), ""
		assert_equal fetch({ title: "x" * 3_000 }), %( title="#{'x' * 3_000}")
		assert_equal @cache.size, 0
	end

	test "reads and writes with [] and []=" do
		@cache[{ id: "a" }] = %( id="a")

		assert_equal @cache[{ id: "a" }], %( id="a")
		assert_equal @cache[{ id: safe_string("a") }], nil
		assert_equal @cache[{ id: "b" }], nil

		@cache[{ id: Set["b"] }] = %( id="b")
		assert_equal @cache.size, 1
	end

	test "doesn't cache attributes whose snapshot would cost more than a value may" do
		# Skipped nils and empty strings render nothing, but the snapshot keeps them.
		assert_equal fetch({ data: { a: "x", b: [nil] * 10_000 } }), %( data-a="x")
		assert_equal fetch({ data: { a: "y", b: [""] * 10_000 } }), %( data-a="y")
		assert_equal fetch({ title: "x", class: [nil] * 10_000 }), %( title="x")
		@cache[{ title: "z", class: [nil] * 10_000 }] = %( title="z")

		assert_equal @cache.size, 0
		assert_equal @cache.bytesize, 0
	end

	test "counts each snapshot against the budget along with its value" do
		fetch({ title: "abc" })

		# The value's 12 bytes, a slot each for the Hash, its key and its value, and the value's bytes.
		assert_equal @cache.bytesize, 12 + (3 * Cache::SLOT_BYTESIZE) + 3
	end

	test "evicts by what each entry cost" do
		cache = Cache.new(max_bytesize: 200)
		20.times { |i| cache.fetch({ title: "t#{i}" }) { Phlex::SGML::Attributes.generate_attributes({ title: "t#{i}" }) } }

		assert cache.bytesize <= 200
		assert cache.size < 20
	end

	test "caches attributes whose snapshot and output exactly fill a value's budget, and no more" do
		[["abc", %( title="abc")], [Phlex::SGML::SafeValue.new("abc"), %( title="abc")]].each do |title, output|
			cost = output.bytesize + (3 * Cache::SLOT_BYTESIZE) + 3

			exact = Cache.new(max_value_bytesize: cost)
			exact.fetch({ title: }) { output }
			exact[{ id: title }] = output
			assert_equal exact.size, 2

			short = Cache.new(max_value_bytesize: cost - 1)
			short.fetch({ title: }) { output }
			short[{ id: title }] = output
			assert_equal short.size, 0
		end
	end

	test "[]= doesn't cache a value larger than a value may be" do
		cache = Cache.new(max_value_bytesize: 5)
		cache[{ id: :a }] = "123456"

		assert_equal cache.size, 0
	end

	test "doesn't freeze the attributes it snapshots" do
		classes = ["a", ["b"]]
		fetch({ class: classes })

		refute classes.frozen?
		refute classes[1].frozen?
	end
end
