# frozen_string_literal: true

class FIFOTest < Quickdraw::Test
	test "expires keys" do
		fifo = Phlex::FIFO.new(max_bytesize: 3)

		100.times do |i|
			fifo[i] = "a"
		end

		assert_equal fifo.size, 3
	end

	test "reading a key" do
		fifo = Phlex::FIFO.new(max_bytesize: 3)

		fifo[0] = "a"

		assert_equal fifo[0], "a"
	end

	test "doesn't retain keys for empty values" do
		fifo = Phlex::FIFO.new(max_bytesize: 2)

		1_000.times do |i|
			fifo[{ i => nil }] = ""
		end

		assert_equal fifo.bytesize, 0
		assert_equal fifo.size, 0
	end

	test "fetch returns empty attribute strings without retaining their keys" do
		fifo = Phlex::FIFO.new(max_bytesize: 2)

		1_000.times do |i|
			attributes = { "data-#{i}" => nil }
			value = fifo.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }

			assert_equal value, ""
		end

		assert_equal fifo.bytesize, 0
		assert_equal fifo.size, 0
	end

	test "empty values don't affect eviction or accounting for nonempty values" do
		fifo = Phlex::FIFO.new(max_bytesize: 2)
		fifo[:first] = "a"
		fifo[:empty] = ""
		fifo[:second] = "b"
		fifo[:third] = "c"

		assert_equal fifo[:first], nil
		assert_equal fifo[:empty], nil
		assert_equal fifo[:second], "b"
		assert_equal fifo[:third], "c"
		assert_equal fifo.bytesize, 2
		assert_equal fifo.size, 2
	end

	test "ignores values that are too large" do
		fifo = Phlex::FIFO.new(max_bytesize: 100, max_value_bytesize: 10)

		fifo[1] = "a" * 10
		fifo[2] = "a" * 11

		assert_equal fifo.size, 1
	end

	test "fetch returns the cached value without yielding" do
		fifo = Phlex::FIFO.new(max_bytesize: 100)
		fifo[1] = "a"

		assert_equal fifo.fetch(1) { raise "should not yield" }, "a"
	end

	test "fetch yields and caches on a miss" do
		fifo = Phlex::FIFO.new(max_bytesize: 100)

		assert_equal fifo.fetch(1) { "a" }, "a"
		assert_equal fifo[1], "a"
	end

	test "fetch yields and caches a nil key on a miss" do
		fifo = Phlex::FIFO.new(max_bytesize: 100)

		assert_equal fifo.fetch(nil) { "a" }, "a"
		assert_equal fifo[nil], "a"
		assert_equal fifo.fetch(nil) { raise "should not yield" }, "a"
	end

	test "fetch returns but doesn't cache values that are too large" do
		fifo = Phlex::FIFO.new(max_bytesize: 100, max_value_bytesize: 10)

		assert_equal fifo.fetch(1) { "a" * 11 }, "a" * 11
		assert_equal fifo.size, 0
	end
end
