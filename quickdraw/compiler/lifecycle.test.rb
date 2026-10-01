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

	# Makes the compiler raise on demand, standing in for a compiler bug.
	module Sabotage
		def self.active = @active

		def self.active=(active)
			@active = active
		end

		def compile(node, **)
			raise "sabotaged" if Sabotage.active

			super
		end
	end

	Phlex::Compiler::MethodCompiler.prepend(Sabotage)

	test "a component that fails to compile on first render is reported once and renders uncompiled" do
		with_component_files(
			"failing.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleFailing < Phlex::HTML
					def view_template = div { "still works" }
				end
			RUBY
		) do
			failures = []
			Sabotage.active = true
			# The handler renders the component itself, which must not deadlock on the compiler lock.
			Phlex::Compiler.enable!(on_failure: -> (component, error) { failures << [component, error.message, component.new.call] })

			begin
				assert_equal LifecycleFailing.new.call, "<div>still works</div>"
				assert_equal LifecycleFailing.new.call, "<div>still works</div>"
			ensure
				Phlex::Compiler.disable!
				Sabotage.active = false
			end

			refute compiled_method?(LifecycleFailing, :view_template)
			assert_equal failures, [[LifecycleFailing, "sabotaged", "<div>still works</div>"]]
			assert_equal Phlex::Compiler.explain(LifecycleFailing).first.message, "compiling LifecycleFailing raised RuntimeError: sabotaged"

			assert_raises(RuntimeError) do
				Sabotage.active = true
				Phlex::Compiler.compile(LifecycleFailing)
			ensure
				Sabotage.active = false
			end
		end
	end

	test "an element redefined after compilation takes effect by recompiling what inlined it" do
		with_component_files(
			"late.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleLate < Phlex::HTML
					def view_template
						div { "parent" }
						span { "kept" }
					end
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleLate)
			first = LifecycleLate.instance_method(:view_template).source_location
			assert compiled_method?(LifecycleLate, :view_template)
			assert_equal LifecycleLate.new.call, "<div>parent</div><span>kept</span>"

			subclass = Class.new(LifecycleLate) { def div(**, &) = plain("subclass div") }
			assert_equal subclass.new.call, "subclass div<span>kept</span>"
			assert_equal LifecycleLate.new.call, "<div>parent</div><span>kept</span>"

			# Recompiled, with span still inlined but div no longer.
			refute_equal LifecycleLate.instance_method(:view_template).source_location, first
			assert compiled_method?(LifecycleLate, :view_template)
			source = File.read(first[0].sub(/ \(compiled \d+\)\z/, ""))
			assert source.include?("div {")

			unrelated = LifecycleLate.new
			unrelated.define_singleton_method(:other) { nil }
			assert_equal unrelated.call, "<div>parent</div><span>kept</span>"

			# An override on one instance can't be compiled for, so it's refused.
			error = assert_raises(Phlex::Compiler::Error) do
				LifecycleLate.new.define_singleton_method(:span) { |**, &| plain("singleton span") }
			end
			assert_equal error.message, "span can't be redefined on a single instance: LifecycleLate compiled it inline. Redefine it on the class, before compiling."

			assert_raises(Phlex::Compiler::Error) do
				LifecycleLate.new.extend(Module.new { def span(**, &) = plain("extended span") })
			end

			# With nothing left to inline, the original definition is reinstalled.
			LifecycleLate.include(Module.new { def span(**, &) = plain("included span") })
			assert_equal LifecycleLate.new.call, "<div>parent</div>included span"
			assert_equal LifecycleLate.new.extend(Module.new { def span(**, &) = plain("extended span") }).call, "<div>parent</div>extended span" # rubocop:disable Lint/DuplicateMethods
		end
	end

	test "an element defined on an ancestor after a descendant compiled takes effect in the descendant" do
		with_component_files(
			"ancestor.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleAncestor < Phlex::HTML
				end
			RUBY
			"descendant.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleDescendant < LifecycleAncestor
					def view_template = div { "descendant" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleDescendant)
			assert_equal LifecycleDescendant.new.call, "<div>descendant</div>"

			LifecycleAncestor.class_eval { def div(**, &) = plain("ancestor div") }
			assert_equal LifecycleDescendant.new.call, "ancestor div"
			assert compiled_method?(LifecycleDescendant, :view_template)

			LifecycleAncestor.include(Module.new { def plain(content) = super("included #{content}") })
			assert_equal LifecycleDescendant.new.call, "included ancestor div"
		end
	end

	test "an element defined later on an included module takes effect by recompiling what inlined it" do
		with_component_files(
			"module_helpers.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleHelpers
				end

				module LifecycleNestedHelpers
				end

				class LifecycleUsesHelpers < Phlex::HTML
					include LifecycleHelpers

					def view_template
						div { "x" }
						span { "y" }
						p { "z" }
					end
				end

				class LifecycleUsesHelpersChild < LifecycleUsesHelpers
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleUsesHelpersChild)
			assert_equal LifecycleUsesHelpersChild.new.call, "<div>x</div><span>y</span><p>z</p>"

			LifecycleHelpers.define_method(:div) { |**| plain("helper div") }
			assert_equal LifecycleUsesHelpers.new.call, "helper div<span>y</span><p>z</p>"
			assert_equal LifecycleUsesHelpersChild.new.call, "helper div<span>y</span><p>z</p>"
			assert compiled_method?(LifecycleUsesHelpers, :view_template)

			# A module mixed into a watched module is watched too.
			LifecycleHelpers.include(LifecycleNestedHelpers)
			LifecycleNestedHelpers.define_method(:span) { |**| plain("nested span") }
			assert_equal LifecycleUsesHelpersChild.new.call, "helper divnested span<p>z</p>"

			# And so is one mixed into the compiled class later.
			later = Module.new
			LifecycleUsesHelpers.include(later)
			later.define_method(:p) { |**| plain("later p") }
			assert_equal LifecycleUsesHelpersChild.new.call, "helper divnested spanlater p"

			later.__send__(:remove_method, :p)
			LifecycleHelpers.__send__(:undef_method, :div)
			assert_raises(NoMethodError) { LifecycleUsesHelpers.new.call }
		end
	end

	test "an element defined later on a module included into a subclass of a compiled class takes effect" do
		with_component_files(
			"inheriting.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleInlinedParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleInheritingChild < LifecycleInlinedParent
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleInheritingChild)

			mixin = Module.new
			LifecycleInheritingChild.include(mixin)
			mixin.define_method(:div) { |**| plain("mixin div") }

			assert_equal LifecycleInheritingChild.new.call, "mixin div"
			assert_equal LifecycleInlinedParent.new.call, "<div>x</div>"
		end
	end

	test "a watched module's own include and prepend keep their return values" do
		with_component_files(
			"returning.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleReturning
					def self.include(*) = (super; :included)
					def self.prepend(*) = (super; :prepended)
				end

				class LifecycleReturningComponent < Phlex::HTML
					include LifecycleReturning

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleReturningComponent)

			assert LifecycleReturning.singleton_class < Phlex::Compiler::MixinHooks
			assert_equal LifecycleReturning.include(Module.new), :included
			assert_equal LifecycleReturning.prepend(Module.new), :prepended
		end
	end

	test "a module with a frozen singleton class is refused before anything is compiled" do
		with_component_files(
			"frozen_singleton.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleFrozenSingleton
				end
				LifecycleFrozenSingleton.singleton_class.freeze

				class LifecycleFrozenSingletonComponent < Phlex::HTML
					include LifecycleFrozenSingleton

					def view_template = div { "x" }
				end
			RUBY
		) do
			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(LifecycleFrozenSingletonComponent) }
			assert_equal error.message, "LifecycleFrozenSingleton can't be watched for changes because its singleton class is frozen, so LifecycleFrozenSingletonComponent can't inline what it defines."
			refute compiled_method?(LifecycleFrozenSingletonComponent, :view_template)
		end
	end

	test "a module mixed into a class that isn't compiled isn't watched" do
		with_component_files(
			"unwatched.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleUnwatchedHelpers
				end

				class LifecycleUnwatched < Phlex::HTML
					include LifecycleUnwatchedHelpers
				end
			RUBY
		) do
			refute LifecycleUnwatchedHelpers.singleton_class < Phlex::Compiler::MixinHooks
		end
	end

	test "a call kept as it was isn't recorded as inlined, so it can still be overridden on an instance" do
		with_component_files(
			"kept.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleKept < Phlex::HTML
					def view_template
						div("positional")
						span { "compiled" }
						section { @text ? "text" : div("positional") }
					end
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleKept)
			assert compiled_method?(LifecycleKept, :view_template)
			assert_equal LifecycleKept.instance_variable_get(:@__phlex_inlined__), Set[:span, :section]

			instance = LifecycleKept.new
			instance.define_singleton_method(:div) { |*, **, &| plain("singleton div") }
			assert_equal instance.call, "singleton div<span>compiled</span><section>singleton div</section>"

			assert_raises(Phlex::Compiler::Error) do
				LifecycleKept.new.define_singleton_method(:span) { |**, &| nil }
			end
		end
	end

	test "freezing a compiled class restores its definitions, so it still follows changes above it" do
		with_component_files(
			"frozen_parent.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleFrozenParent < Phlex::HTML
				end
			RUBY
			"frozen_child.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleFrozenChild < LifecycleFrozenParent
					def view_template = div { "child" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleFrozenChild)
			assert_equal LifecycleFrozenChild.instance_variable_get(:@__phlex_inlined__), Set[:div]

			LifecycleFrozenChild.freeze
			assert LifecycleFrozenChild.frozen?
			assert_equal LifecycleFrozenChild.new.call, "<div>child</div>"
			assert_equal LifecycleFrozenChild.instance_variable_get(:@__phlex_inlined__), Set[]

			LifecycleFrozenParent.class_eval { def div(**, &) = plain("parent div") }
			assert_equal LifecycleFrozenChild.new.call, "parent div"
		end
	end

	test "refined elements keep their calls while unaffected elements compile" do
		with_component_files(
			"refined_elements.rb" => <<~RUBY,
				module LifecycleElementRefinements
					refine Phlex::HTML do
						def div(**attributes, &block) = span(**attributes, &block)
						def br(**attributes) = hr(**attributes)
					end
				end

				using LifecycleElementRefinements

				class LifecycleRefinedElements < Phlex::HTML
					def view_template
						div(class: "greeting") { "hello" }
						br(class: "break")
						section { div { "nested" } }
					end
				end
			RUBY
			"unrefined_elements.rb" => <<~RUBY
				class LifecycleUnrefinedElements < Phlex::HTML
					def view_template = div { "hello" }
				end
			RUBY
		) do
			expected = '<span class="greeting">hello</span><hr class="break"><section><span>nested</span></section>'
			assert_equal LifecycleRefinedElements.call, expected

			Phlex::Compiler.compile(LifecycleRefinedElements)
			Phlex::Compiler.compile(LifecycleUnrefinedElements)

			assert compiled_method?(LifecycleRefinedElements, :view_template)
			assert_equal LifecycleRefinedElements.call, expected
			assert_equal LifecycleRefinedElements.instance_variable_get(:@__phlex_inlined__), Set[:section]
			assert compiled_method?(LifecycleUnrefinedElements, :view_template)
			assert_equal LifecycleUnrefinedElements.call, "<div>hello</div>"
		end
	end

	test "refined helpers preserve their output and return values" do
		with_component_files(
			"refined_helpers.rb" => <<~RUBY
				module LifecycleHelperRefinements
					refine Phlex::SGML do
						def plain(value) = "refined " + value
						def safe(value) = super("<b>" + value + "</b>")
					end

					refine Phlex::HTML do
						def doctype = span { "doctype" }
					end
				end

				using LifecycleHelperRefinements

				class LifecycleRefinedHelpers < Phlex::HTML
					def view_template
						doctype
						div { plain "hello" }
						raw safe("hello")
					end
				end
			RUBY
		) do
			expected = "<span>doctype</span><div>refined hello</div><b>hello</b>"
			assert_equal LifecycleRefinedHelpers.call, expected

			Phlex::Compiler.compile(LifecycleRefinedHelpers)

			assert compiled_method?(LifecycleRefinedHelpers, :view_template)
			assert_equal LifecycleRefinedHelpers.call, expected
		end
	end

	test "a refinement of a descendant prevents inlining in an inherited method" do
		with_component_files(
			"refined_descendant.rb" => <<~RUBY
				class LifecycleRefinedParent < Phlex::HTML
				end

				class LifecycleRefinedChild < LifecycleRefinedParent
				end

				module LifecycleDescendantRefinements
					refine LifecycleRefinedChild do
						def div(**attributes, &block) = span(**attributes, &block)
					end
				end

				using LifecycleDescendantRefinements

				class LifecycleRefinedParent
					def view_template
						section { div { "hello" } }
					end
				end
			RUBY
		) do
			assert_equal LifecycleRefinedParent.call, "<section><div>hello</div></section>"
			assert_equal LifecycleRefinedChild.call, "<section><span>hello</span></section>"

			Phlex::Compiler.compile(LifecycleRefinedChild)

			assert compiled_method?(LifecycleRefinedParent, :view_template)
			assert_equal LifecycleRefinedParent.call, "<section><div>hello</div></section>"
			assert_equal LifecycleRefinedChild.call, "<section><span>hello</span></section>"
		end
	end

	test "refinements of the methods the resolver calls don't break compilation" do
		with_component_files(
			"refined_call.rb" => <<~RUBY,
				module LifecycleCallRefinements
					refine(Method) { def call(*) = :refined }
				end

				using LifecycleCallRefinements

				class LifecycleRefinedCall < Phlex::HTML
					def view_template = div { "hello" }
				end
			RUBY
			"refined_bind.rb" => <<~RUBY
				module LifecycleBindRefinements
					refine(UnboundMethod) { def bind(*) = :refined }

					refine Phlex::HTML do
						def div(**attributes, &block) = span(**attributes, &block)
					end
				end

				using LifecycleBindRefinements

				class LifecycleRefinedBind < Phlex::HTML
					def view_template = div { "hello" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleRefinedCall)
			Phlex::Compiler.compile(LifecycleRefinedBind)

			refute LifecycleRefinedCall.instance_variable_get(:@__phlex_inlined__)
			assert_equal LifecycleRefinedCall.call, "<div>hello</div>"
			refute LifecycleRefinedBind.instance_variable_get(:@__phlex_inlined__)
			assert_equal LifecycleRefinedBind.call, "<span>hello</span>"
		end
	end

	test "a refinement used by one compiled file doesn't reach another" do
		with_component_files(
			"refined.rb" => <<~RUBY,
				# frozen_string_literal: true
				module LifecycleShout
					refine(String) { def shout = upcase + "!" }
				end

				using LifecycleShout

				class LifecycleRefined < Phlex::HTML
					def view_template = div { "hi".shout }
				end
			RUBY
			"unrefined.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleUnrefined < Phlex::HTML
					def view_template = div { "hi".respond_to?(:shout).to_s }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleRefined)
			Phlex::Compiler.compile(LifecycleUnrefined)

			assert_equal LifecycleRefined.new.call, "<div>HI!</div>"
			assert_equal LifecycleUnrefined.new.call, "<div>false</div>"
		end
	end

	test "include and prepend still return the class, and only the component's own methods are compiled" do
		with_component_files(
			"mixed_in.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleMixin
					def content = span { "mixin" }
				end

				class LifecycleMixedIn < Phlex::HTML
					def view_template
						div { content }
						flush
					end
				end
			RUBY
		) do
			assert LifecycleMixedIn.include(LifecycleMixin).equal?(LifecycleMixedIn)
			assert LifecycleMixedIn.prepend(Module.new).equal?(LifecycleMixedIn)
			LifecycleMixedIn.__send__(:private, :content)

			Phlex::Compiler.compile(LifecycleMixedIn)

			assert compiled_method?(LifecycleMixedIn, :view_template)
			refute compiled_method?(LifecycleMixedIn, :content)
			assert_equal LifecycleMixedIn.new.call, "<div><span>mixin</span></div>"

			# flush was recognised but kept as a call, so overriding it is fine.
			instance = LifecycleMixedIn.new
			instance.define_singleton_method(:flush) { nil }
			assert_equal instance.call, "<div><span>mixin</span></div>"
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

	test "cache keys are the same before and after compilation" do
		with_component_files(
			"cached.rb" => <<~RUBY
				# frozen_string_literal: true
				require "json"

				class LifecycleCached < Phlex::HTML
					STORE = Class.new do
						attr_reader :keys

						def initialize = @keys = []

						def fetch(key)
							@keys << key
							yield
						end
					end.new

					def view_template
						cache(:a) { div { "cached" } }
					end

					private def cache_store = STORE
				end
			RUBY
		) do
			LifecycleCached.new.call
			Phlex::Compiler.compile(LifecycleCached)
			LifecycleCached.new.call

			assert compiled_method?(LifecycleCached, :view_template)
			assert_equal LifecycleCached::STORE.keys.uniq.length, 1
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
