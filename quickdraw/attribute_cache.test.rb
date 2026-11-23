# frozen_string_literal: true

class AttributeCacheTest < Quickdraw::Test
	Cache = Phlex::AttributeCache
	SafeString = Class.new(String) { include Phlex::SGML::SafeObject }

	def setup
		@cache = Cache.new(max_bytesize: 2 ** 20)
	end

	private def fetch(attributes) = (@cache[attributes] ||= Phlex::SGML::Attributes.generate_attributes(attributes))

	test "hits with an equal hash of plain values" do
		attributes = { id: "a", class: ["b", :c, nil], data: { d: 1, e: true, f: false }, title: Phlex::SGML::SafeValue.new("t") }
		fetch(attributes)

		assert_equal @cache[{ id: "a", class: ["b", :c, nil], data: { d: 1, e: true, f: false }, title: attributes[:title] }], fetch(attributes)
		assert_equal @cache.size, 1
	end

	test "never answers for a plain string with a safe one's output" do
		fetch({ id: "a", onclick: Phlex::SGML::SafeValue.new("x()") })

		assert_equal @cache[{ id: "a", onclick: "x()" }], nil
		assert_raises(Phlex::ArgumentError) { fetch({ id: "a", onclick: "x()" }) }
	end

	test "misses when a string is safe, or a subclass, but the cached one isn't" do
		fetch({ id: "a", href: "javascript:x()" })

		assert_equal @cache[{ id: "a", href: SafeString.new("javascript:x()") }], nil
		assert_equal @cache[{ id: "a", href: Class.new(String).new("javascript:x()") }], nil
		assert_equal fetch({ id: "a", href: Phlex::SGML::SafeValue.new("javascript:x()") }), %( id="a" href="javascript:x()")
	end

	test "misses when the pairs are in another order" do
		fetch({ "title" => "a", :title => "b" })

		assert_equal @cache[{ :title => "b", "title" => "a" }], nil
	end

	test "doesn't cache attributes whose snapshot would cost more than a value may" do
		# Skipped nils render nothing, but the snapshot keeps them.
		assert_equal fetch({ data: { a: "x", b: [nil] * 10_000 } }), %( data-a="x")
		assert_equal fetch({ title: "x", class: [nil] * 10_000 }), %( title="x")

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
		20.times { |i| cache[{ title: "t#{i}" }] ||= Phlex::SGML::Attributes.generate_attributes({ title: "t#{i}" }) }

		assert cache.bytesize <= 200
		assert cache.size < 20
	end
end
