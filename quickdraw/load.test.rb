# frozen_string_literal: true

class LoadTest < Quickdraw::Test
	test "requiring phlex makes Date available" do
		script = <<~RUBY
			require "phlex"

			Phlex::SGML::Attributes
			print defined?(Date)
		RUBY

		output = IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out], &:read)
		assert_equal $?.exitstatus, 0
		assert_equal output, "constant"
	end
end
