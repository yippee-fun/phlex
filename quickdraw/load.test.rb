# frozen_string_literal: true

class LoadTest < Quickdraw::Test
	def run_script(script)
		output = IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out], &:read)
		assert_equal $?.exitstatus, 0
		output
	end

	test "collection attributes work after requiring only phlex" do
		output = run_script(<<~RUBY)
			require "phlex"
			print Phlex::HTML.new.call { |c| c.div(class: ["a", "b"], data: { controller: "c" }) }
		RUBY

		assert_equal output, '<div class="a b" data-controller="c"></div>'
	end

	test "JSON escaping works after requiring only phlex" do
		output = run_script(<<~RUBY)
			require "phlex"
			print Phlex::HTML.new.json_escape("</script>")
		RUBY

		assert_equal output, "\\u003c/script\\u003e"
	end

	test "the FIFO cache works after requiring only phlex" do
		output = run_script(<<~RUBY)
			require "phlex"

			store = Phlex::FIFOCacheStore.new
			print store.fetch("key") { "cached" }
			print store.fetch("key") { raise "unexpected cache miss" }
		RUBY

		assert_equal output, "cachedcached"
	end
end
