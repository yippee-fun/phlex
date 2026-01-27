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
end
