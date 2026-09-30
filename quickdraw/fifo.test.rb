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
