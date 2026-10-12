# frozen_string_literal: true

require "tmpdir"

class RactorTest < Quickdraw::Test
	class Example < Phlex::HTML
		register_element :trix_editor

		def view_template
			div(class: "card", id: "example") do
				span(data: { count: 1 }) { "Hello" }
				img(src: "/a.png", alt: "a")
				trix_editor(class: "custom") { "Custom" }
				svg(viewBox: "0 0 1 1") { |s| s.path(d: "M0 0") }
			end
		end
	end

	def self.run_in_ractor(&)
		experimental = Warning[:experimental]
		Warning[:experimental] = false
		ractor = Ractor.new(&)
		ractor.respond_to?(:value) ? ractor.value : ractor.take
	ensure
		Warning[:experimental] = experimental
	end

	def run_in_ractor(&) = self.class.run_in_ractor(&)

	# Ractor-local storage needs Ruby 3.4+; TruffleRuby and JRuby have no Ractors.
	RACTORS = defined?(::Ractor) && ::Ractor.respond_to?(:store_if_absent)

	# Phlex escapes text through ERB::Escape, whose html_escape is only marked
	# Ractor-safe since erb 5.0.2 — whether the render test runs depends on the
	# erb in the bundle (Ruby 4.0 ships a safe one; Ruby 3.3 and 3.4 do not).
	ERB_ESCAPE_RACTOR_SAFE =
		RACTORS && begin
			report = Thread.report_on_exception
			Thread.report_on_exception = false
			run_in_ractor { ERB::Escape.html_escape("<") } == "&lt;"
		rescue ::Ractor::Error
			false
		ensure
			Thread.report_on_exception = report
		end

	test "the main Ractor uses ATTRIBUTE_CACHE" do
		assert_equal Phlex.attribute_cache.equal?(Phlex::ATTRIBUTE_CACHE), true
	end

	if RACTORS
		test "a non-main Ractor gets its own attribute cache" do
			main_cache_id = Phlex::ATTRIBUTE_CACHE.object_id
			ractor_cache_ids = run_in_ractor { [Phlex.attribute_cache.object_id, Phlex.attribute_cache.object_id] }

			assert_equal ractor_cache_ids.uniq.size, 1
			assert_equal ractor_cache_ids.include?(main_cache_id), false
		end

		test "a non-main Ractor's cache is as large as the main one" do
			assert_equal run_in_ractor { Phlex.attribute_cache.max_bytesize }, Phlex::ATTRIBUTE_CACHE.max_bytesize
		end

		test "a non-main Ractor's cache grows with templates defined after it was created" do
			experimental = Warning[:experimental]
			Warning[:experimental] = false
			ractor = Ractor.new do
				Ractor.main << Phlex.attribute_cache.max_bytesize # before
				Ractor.receive
				Phlex.attribute_cache.max_bytesize # after
			end

			before = Ractor.receive
			Phlex.__expand_attribute_cache__(File.expand_path("../bench.rb", __dir__))
			expected = Phlex::ATTRIBUTE_CACHE.max_bytesize

			ractor << :go
			after = ractor.respond_to?(:value) ? ractor.value : ractor.take

			assert_equal after, expected
			assert_equal after > before, true
		ensure
			Warning[:experimental] = experimental
		end
	end

	if ERB_ESCAPE_RACTOR_SAFE
		test "renders inside a non-main Ractor with the same output" do
			assert_equal run_in_ractor { Example.call }, Example.call
		end

		test "renders inside a non-main Ractor with lazy compilation enabled" do
			Dir.mktmpdir do |dir|
				path = File.join(dir, "ractor_lazy.rb")
				File.write(path, <<~RUBY)
					# frozen_string_literal: true
					class RactorLazyCompiled < Phlex::HTML
						def view_template = div(class: "compiled") { "compiled" }
					end

					class RactorLazyUncompiled < Phlex::HTML
						def view_template = div(class: "uncompiled") { "uncompiled" }
					end
				RUBY
				load path

				Phlex::Compiler.enable!
				begin
					expected = RactorLazyCompiled.call # the main Ractor compiles it

					assert_equal run_in_ractor { RactorLazyCompiled.call }, expected
					assert_equal run_in_ractor { RactorLazyUncompiled.call }, %(<div class="uncompiled">uncompiled</div>)
				ensure
					Phlex::Compiler.disable!
				end
			end
		end
	end
end
