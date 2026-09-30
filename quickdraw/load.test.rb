# frozen_string_literal: true

class LoadTest < Quickdraw::Test
	test "JSON escaping works after requiring only phlex" do
		script = <<~RUBY
			require "phlex"
			print Phlex::HTML.new.json_escape("</script>")
		RUBY

		output = IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out], &:read)
		assert_equal $?.exitstatus, 0
		assert_equal output, '\u003c/script\u003e'
	end

	test "the FIFO cache works after requiring only phlex" do
		script = <<~RUBY
			require "phlex"

			store = Phlex::FIFOCacheStore.new
			print store.fetch(:key) { "cached" }
			print store.fetch(:key) { raise "unexpected cache miss" }
		RUBY

		output = IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out], &:read)
		assert_equal $?.exitstatus, 0
		assert_equal output, "cachedcached"
	end

	test "loading and rendering HTML and SVG with verbose warnings is quiet" do
		script = <<~RUBY
			require "phlex"
			$VERBOSE = true

			class Greeting < Phlex::HTML
				def view_template(&block)
					div { yield }
					br
					svg { |s| s.circle(cx: 1, cy: 2, r: 3) }
				end
			end

			print Greeting.new { "Hello" }.call
		RUBY

		output = IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out], &:read)
		assert_equal $?.exitstatus, 0
		assert_equal output, '<div>Hello</div><br><svg><circle cx="1" cy="2" r="3"></circle></svg>'
	end

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
