# frozen_string_literal: true

require "tmpdir"

class RactorTest < Quickdraw::Test
	class Example < Phlex::HTML
		register_element :trix_editor

		def view_template
			div(class: "card", id: "example") do
				span(data: { count: 1 }) { "Hello & goodbye" }
				img(src: "/a.png", alt: "a")
				trix_editor(class: "custom") { "Custom" }
				svg(viewBox: "0 0 1 1") { |s| s.path(d: "M0 0") }
			end
		end
	end

	class TagExample < Phlex::HTML
		register_element :trix_editor
		__register_void_element__ :trix_break

		def view_template
			tag(:div, class: "a") { "x" }
			tag(:img, src: "/a.png", srcset: ["/a.png 1x", "/b.png 2x"])
			tag(:trix_editor, class: "b") { "registered" }
			tag(:trix_break)
			tag(:my_widget, data: { k: 1 }) { "w" }
			tag(:svg, viewBox: "0 0 1 1") { |s| s.tag(:path, d: "M0 0") }
			tag(:br)
		end
	end

	class TagExampleChild < TagExample
	end

	class Cached < Phlex::HTML
		def cache_store = Ractor.current[:ractor_test_cache_store] ||= Phlex::FIFOCacheStore.new

		def view_template = cache { div { "cached" } }
	end

	class Table < Phlex::CSV
		def escape_csv_injection? = true

		def row_template(number)
			column("number", number)
			column("text", "=#{number}")
		end
	end

	def in_ractor(&)
		experimental = Warning[:experimental]
		Warning[:experimental] = false
		ractor = Ractor.new(&)
		ractor.respond_to?(:value) ? ractor.value : ractor.take
	ensure
		Warning[:experimental] = experimental
	end

	def with_component_file(source)
		Dir.mktmpdir do |dir|
			path = File.join(dir, "component.rb")
			File.write(path, source)
			load path
			yield
		end
	end

	test "the main Ractor uses ATTRIBUTE_CACHE" do
		assert Phlex.__attribute_cache__.equal?(Phlex::ATTRIBUTE_CACHE)
	end

	if defined?(::Ractor)
		test "another Ractor gets one attribute cache of its own" do
			main_cache_id = Phlex::ATTRIBUTE_CACHE.object_id
			cache_ids = in_ractor { [Phlex.__attribute_cache__.object_id, Phlex.__attribute_cache__.object_id] }

			assert_equal cache_ids.uniq.size, 1
			refute cache_ids.include?(main_cache_id)
		end

		test "another Ractor's attribute cache is as large as the main one" do
			assert_equal in_ractor { Phlex.__attribute_cache__.max_bytesize }, Phlex::ATTRIBUTE_CACHE.max_bytesize
		end

		test "another Ractor's attribute cache grows with templates defined after it was created" do
			experimental = Warning[:experimental]
			Warning[:experimental] = false

			ractor = Ractor.new do
				Ractor.main << begin
					Phlex.__attribute_cache__.max_bytesize
				rescue Exception => e
					e
				end

				Ractor.receive
				Phlex.__attribute_cache__.max_bytesize
			end

			before = Ractor.receive
			raise before if Exception === before

			Dir.mktmpdir do |dir|
				path = File.join(dir, "template.rb")
				File.write(path, "#" * 100)
				Phlex.__expand_attribute_cache__(path)
			end

			ractor << :expanded
			after = ractor.respond_to?(:value) ? ractor.value : ractor.take

			assert_equal after, before + 100
			assert_equal after, Phlex::ATTRIBUTE_CACHE.max_bytesize
		ensure
			Warning[:experimental] = experimental
		end

		test "renders the same in another Ractor" do
			expected = Example.call

			assert_equal in_ractor { Example.call }, expected
		end

		test "tag finds built-in and registered elements in another Ractor" do
			expected = [TagExample.call, TagExampleChild.call]

			assert_equal in_ractor { [TagExample.call, TagExampleChild.call] }, expected
		end

		test "renders CSV in another Ractor" do
			expected = Table.new([1, 2]).call

			assert_equal in_ractor { Table.new([1, 2]).call }, expected
		end

		test "caches a fragment in another Ractor" do
			assert_equal in_ractor { [Cached.call, Cached.call] }, [%(<div>cached</div>)] * 2
		end

		test "a compiled component's error keeps its class and maps to the source in another Ractor" do
			with_component_file(<<~RUBY) do
				# frozen_string_literal: true
				class RactorRaising < Phlex::HTML
					def view_template
						div { raise ArgumentError, "boom" }
					end
				end
			RUBY
				Phlex::Compiler.compile(RactorRaising)
				source_path = Phlex.__compiled_source_maps__.fetch(RactorRaising.instance_method(:view_template).source_location[0]).path

				error_class, message, location = in_ractor do
					Thread.current.report_on_exception = false
					RactorRaising.call
				rescue ArgumentError => e
					[e.class, e.message, e.backtrace.first]
				end

				assert_equal [error_class, message], [ArgumentError, "boom"]
				assert location.start_with?("#{source_path}:4:")
			end
		end

		test "only the main Ractor compiles on first render" do
			with_component_file(<<~RUBY) do
				# frozen_string_literal: true
				class RactorLazy < Phlex::HTML
					def view_template = div(class: "lazy") { "lazy" }
				end
			RUBY
				Phlex::Compiler.enable!
				begin
					assert_equal in_ractor { RactorLazy.call }, %(<div class="lazy">lazy</div>)
					refute Phlex::Compiler.compiled?(RactorLazy)

					RactorLazy.call
					assert Phlex::Compiler.compiled?(RactorLazy)
					assert_equal in_ractor { RactorLazy.call }, %(<div class="lazy">lazy</div>)
				ensure
					Phlex::Compiler.disable!
				end
			end
		end
	end
end
