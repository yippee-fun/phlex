# frozen_string_literal: true

require "tmpdir"

class CompilerLifecycleTest < Quickdraw::Test
	Phlex::Compiler

	def compiled_method?(component, name)
		Phlex::Compiler::MAP.key?(component.instance_method(name).source_location[0])
	end

	def with_component_files(files)
		Dir.mktmpdir do |dir|
			paths = files.map do |name, source|
				path = File.join(dir, name)
				File.write(path, source)
				path
			end

			paths.each { |path| load path }
			yield paths
		end
	end

	test "compiling twice leaves the first compilation in place" do
		with_component_files(
			"once.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleOnce < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
		) do |(path)|
			Phlex::Compiler.compile(LifecycleOnce)
			first = LifecycleOnce.instance_method(:view_template).source_location
			assert compiled_method?(LifecycleOnce, :view_template)

			Phlex::Compiler.compile(LifecycleOnce)
			Phlex::Compiler.compile_file(path)
			assert_equal LifecycleOnce.instance_method(:view_template).source_location, first
			assert_equal LifecycleOnce.new.call, "<div>x</div>"
		end
	end

	test "compile covers methods defined in other files and in ancestors" do
		with_component_files(
			"parent.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleParent < Phlex::HTML
					def view_template
						header
						body_content
					end

					def header = h1 { "Parent" }
				end
			RUBY
			"child.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleChild < LifecycleParent
					def body_content = p { "Child" }
				end
			RUBY
			"child_extra.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleChild
					def footer = footer_content
					def footer_content = span { "Footer" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleChild)

			refute compiled_method?(LifecycleParent, :view_template) # nothing to inline
			assert compiled_method?(LifecycleParent, :header)
			assert compiled_method?(LifecycleChild, :body_content)
			assert compiled_method?(LifecycleChild, :footer_content)
			assert Phlex::Compiler.compiled?(LifecycleChild)
			assert Phlex::Compiler.compiled?(LifecycleParent)
			assert_equal LifecycleChild.new.call, "<h1>Parent</h1><p>Child</p>"
		end
	end

	test "lazy compilation compiles a component on its first render" do
		with_component_files(
			"lazy.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleLazy < Phlex::HTML
					def view_template = div { "lazy" }
				end
			RUBY
		) do
			refute compiled_method?(LifecycleLazy, :view_template)

			Phlex::Compiler.enable!
			begin
				assert_equal LifecycleLazy.new.call, "<div>lazy</div>"
				assert compiled_method?(LifecycleLazy, :view_template)
				assert_equal LifecycleLazy.new.call, "<div>lazy</div>"
			ensure
				Phlex::Compiler.disable!
			end
		end
	end

	test "exceptions map to the right line after the file is reloaded with more lines" do
		with_component_files(
			"reloaded.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleReloaded < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
		) do |(path)|
			Phlex::Compiler.compile(LifecycleReloaded)
			Object.__send__(:remove_const, :LifecycleReloaded)

			File.write(path, <<~RUBY)
				# frozen_string_literal: true
				class LifecycleReloaded < Phlex::HTML
					def view_template = div { boom }

					def boom
						raise "boom"
					end
				end
			RUBY
			load path
			Phlex::Compiler.compile(LifecycleReloaded)

			error = assert_raises(RuntimeError) { LifecycleReloaded.new.call }
			assert_equal error.backtrace.grep(/reloaded\.rb:\d+/).first[/:(\d+):/, 1], "6"
		end
	end

	test "anonymous and frozen components are left alone" do
		component = Class.new(Phlex::HTML) do
			def view_template = div { "anon" }
		end

		Phlex::Compiler.compile(component)
		assert Phlex::Compiler.compiled?(component)
		assert_equal component.new.call, "<div>anon</div>"

		frozen = Class.new(Phlex::HTML) do
			def view_template = div { "frozen" }
		end.freeze

		Phlex::Compiler.compile(frozen)
		refute Phlex::Compiler.compiled?(frozen)
		assert_equal frozen.new.call, "<div>frozen</div>"
	end

	test "a class whose constant was removed still renders lazily" do
		with_component_files(
			"gone.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleGone
					class View < Phlex::HTML
						def view_template = div { "gone" }
					end
				end
			RUBY
		) do
			old = LifecycleGone::View
			Object.__send__(:remove_const, :LifecycleGone)

			Phlex::Compiler.enable!
			begin
				assert_equal old.new.call, "<div>gone</div>"
			ensure
				Phlex::Compiler.disable!
			end
		end
	end

	test "a descendant that undefines an element doesn't stop the parent compiling" do
		with_component_files(
			"undef.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleUndefParent < Phlex::HTML
					def view_template
						div { "d" }
						span { "s" }
					end
				end

				class LifecycleUndefChild < LifecycleUndefParent
					undef_method :span
					def view_template = plain("fine")
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleUndefParent)
			assert compiled_method?(LifecycleUndefParent, :view_template)
			assert_equal LifecycleUndefParent.new.call, "<div>d</div><span>s</span>"
			assert_equal LifecycleUndefChild.new.call, "fine"
		end
	end
end
