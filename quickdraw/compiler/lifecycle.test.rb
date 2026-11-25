# frozen_string_literal: true

require "tmpdir"
require "weakref"
require "compiler_helper"

class CompilerLifecycleTest < Quickdraw::Test
	include CompilerHelper

	Phlex::Compiler

	def compiled_method?(component, name)
		Phlex.__compiled_source_maps__.key?(component.instance_method(name).source_location[0])
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

	test "a lazy render of a compiled component waits for a recompilation in progress" do
		with_component_files(
			"waits.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleWaits < Phlex::HTML
					def view_template = div { "waits" }
				end
			RUBY
		) do
			with_lazy_compilation do
				LifecycleWaits.call
				assert Phlex::Compiler.compiled?(LifecycleWaits)

				locked = Queue.new
				release = Queue.new
				Pause.gate = -> {
					Pause.gate = nil
					locked << true
					release.pop
				}
				recompiling = Thread.new { Phlex::Compiler.recompile(LifecycleWaits) }
				locked.pop

				render = Thread.new { LifecycleWaits.call }
				deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
				Thread.pass until render.status == "sleep" || !render.alive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

				assert render.alive?
				release << true
				assert_equal render.value, "<div>waits</div>"
				recompiling.join
			ensure
				Pause.gate = nil
				release&.<< true
			end
		end
	end

	test "a lazy render of a compiled component doesn't wait for another component compiling" do
		with_component_files(
			"prompt.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecyclePrompt < Phlex::HTML
					def view_template = div { "prompt" }
				end
			RUBY
		) do
			with_lazy_compilation do
				LifecyclePrompt.call
				assert Phlex::Compiler.compiled?(LifecyclePrompt)

				locked = Queue.new
				release = Queue.new
				compiling = Thread.new do
					Phlex::Compiler::MUTEX.synchronize do
						locked << true
						release.pop
					end
				end
				locked.pop

				render = Thread.new { LifecyclePrompt.call }

				finished = render.join(2)
				release << true

				assert finished
				assert_equal render.value, "<div>prompt</div>"
				compiling.join
			ensure
				release&.<< true
			end
		end
	end

	test "a compiled method's source map exists by the time the method does" do
		with_component_files(
			"mapped.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleMapped < Phlex::HTML
					MAPPED = []

					def self.method_added(name)
						MAPPED << Phlex.__compiled_source_maps__.key?(instance_method(name).source_location[0])
						super
					end

					def view_template = div { "mapped" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleMapped)

			assert_equal LifecycleMapped::MAPPED, [false, true]
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

			with_lazy_compilation do
				assert_equal LifecycleLazy.new.call, "<div>lazy</div>"
				assert compiled_method?(LifecycleLazy, :view_template)
				assert_equal LifecycleLazy.new.call, "<div>lazy</div>"
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
			raise((Class === Sabotage.active) ? Sabotage.active : RuntimeError, "sabotaged") if Sabotage.active

			super
		end
	end

	Phlex::Compiler::MethodCompiler.prepend(Sabotage)

	# Calls the gate, if set, as the compiler compiles each method.
	module Pause
		def self.gate = @gate

		def self.gate=(gate)
			@gate = gate
		end

		def compile(node, **)
			Pause.gate&.call

			super
		end
	end

	Phlex::Compiler::MethodCompiler.prepend(Pause)

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
			with_lazy_compilation(on_failure: -> (component, error) { failures << [component, error.message, component.new.call] }) do
				assert_equal LifecycleFailing.new.call, "<div>still works</div>"
				assert_equal LifecycleFailing.new.call, "<div>still works</div>"
			ensure
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

	test "a subclass overriding equal? after compilation stops guarded blocks trusting it" do
		with_component_files(
			"identity.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIdentity < Phlex::HTML
					def view_template
						impostor = Object.new
						impostor.define_singleton_method(:br) { nil }
						impostor.instance_exec(&block_of { br })
						plain "ok"
					end

					def block_of(&block) = block
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleIdentity)
			assert_equal LifecycleIdentity.new.call, "ok"

			trusting = Class.new(LifecycleIdentity) { def equal?(_) = true }
			assert_equal trusting.new.call, "ok"
			assert_equal LifecycleIdentity.new.call, "ok"
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

			extended_span = Module.new { def span(**, &) = plain("extended span") }

			assert_raises(Phlex::Compiler::Error) do
				LifecycleLate.new.extend(extended_span)
			end

			# With nothing left to inline, the original definition is reinstalled.
			LifecycleLate.include(Module.new { def span(**, &) = plain("included span") })
			assert_equal LifecycleLate.new.call, "<div>parent</div>included span"
			assert_equal LifecycleLate.new.extend(extended_span).call, "<div>parent</div>extended span"
		end
	end

	test "re-registering an element after compilation renders its new tag" do
		with_component_files(
			"reregistered.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleReregistered < Phlex::HTML
					register_element :widget, tag: "old-widget"
					__register_void_element__ :marker, tag: "old-marker"

					def view_template
						widget { "x" }
						marker
					end
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleReregistered)
			assert_equal LifecycleReregistered.call, "<old-widget>x</old-widget><old-marker>"

			LifecycleReregistered.register_element :widget, tag: "new-widget"
			assert_equal LifecycleReregistered.call, "<new-widget>x</new-widget><old-marker>"

			LifecycleReregistered.__register_void_element__ :marker, tag: "new-marker"
			assert compiled_method?(LifecycleReregistered, :view_template)
			assert_equal LifecycleReregistered.call, "<new-widget>x</new-widget><new-marker>"
		end
	end

	test "recompiling leaves a method above a `using` that never compiled alone" do
		with_component_files(
			"boundary.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleShout
					refine(String) { def shout = upcase }
				end

				class LifecycleBoundary < Phlex::HTML
					def label = "label"
				end

				using LifecycleShout

				class LifecycleBoundary
					def view_template = div { label.shout }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleBoundary)
			assert compiled_method?(LifecycleBoundary, :view_template)
			assert_equal LifecycleBoundary.new.call, "<div>LABEL</div>"

			LifecycleBoundary.include(Module.new { def div(**, &) = plain("included div") })
			assert_equal LifecycleBoundary.new.call, "included div"
			refute compiled_method?(LifecycleBoundary, :label)
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
			assert_equal LifecycleKept.instance_variable_get(:@__phlex_inlined__), Set[:span, :section, :block_given?]

			instance = LifecycleKept.new
			instance.define_singleton_method(:div) { |*, **, &| plain("singleton div") }
			assert_equal instance.call, "singleton div<span>compiled</span><section>singleton div</section>"

			assert_raises(Phlex::Compiler::Error) do
				LifecycleKept.new.define_singleton_method(:span) { |**, &| nil }
			end
		end
	end

	test "a component that inlined an svg block is recompiled when Phlex::SVG changes" do
		with_component_files(
			"icon.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIcon < Phlex::HTML
					def view_template = svg { |s| s.path(d: "M0") }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleIcon)
			assert LifecycleIcon.instance_variable_get(:@__phlex_inlined_svg__).include?(:path)
			before = LifecycleIcon.instance_method(:view_template).source_location

			# Aliasing a method to itself redefines it without changing it.
			Phlex::SVG.class_eval { alias_method :path, :path }

			refute_equal LifecycleIcon.instance_method(:view_template).source_location, before
			assert_equal LifecycleIcon.new.call, %(<svg><path d="M0"></path></svg>)
		end
	end

	test "a component that inlined an svg block is recompiled when Phlex::SVG.new changes" do
		with_component_files(
			"icon.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIconNew < Phlex::HTML
					def view_template = svg { |s| s.circle(r: 1) }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleIconNew)
			assert LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__).include?(:new)
			before = LifecycleIconNew.instance_method(:view_template).source_location

			begin
				Phlex::SVG.define_singleton_method(:new, Phlex::SGML.singleton_class.instance_method(:new))

				refute_equal LifecycleIconNew.instance_method(:view_template).source_location, before
				refute LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:new)
				assert_equal LifecycleIconNew.new.call, %(<svg><circle r="1"></circle></svg>)

				Phlex::SVG.singleton_class.remove_method(:new)
				Phlex::Compiler.recompile(LifecycleIconNew)
				assert LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__).include?(:new)

				Phlex::SVG.singleton_class.undef_method(:new)
				refute LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:new)
				assert_raises(NoMethodError) { LifecycleIconNew.new.call }

				restore_svg_new
				Phlex::Compiler.recompile(LifecycleIconNew)
				assert LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__).include?(:new)

				Phlex::SVG.singleton_class.__send__(:private, :new)
				refute LifecycleIconNew.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:new)
				assert_raises(NoMethodError) { LifecycleIconNew.new.call }
			ensure
				restore_svg_new
			end
		end
	end

	# Replacing an undefined method is the only way to remove it on CRuby.
	private def restore_svg_new
		Phlex::SVG.define_singleton_method(:new, Phlex::SGML.singleton_class.instance_method(:new))
		Phlex::SVG.singleton_class.remove_method(:new)
	end

	test "a component that inlined an svg block is recompiled when Phlex::SVG redefines block_given?" do
		with_component_files(
			"icon.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIconBlockGiven < Phlex::HTML
					def view_template = svg { |s| s.circle(r: 1) }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleIconBlockGiven)
			assert LifecycleIconBlockGiven.instance_variable_get(:@__phlex_inlined_svg__).include?(:block_given?)
			before = LifecycleIconBlockGiven.instance_method(:view_template).source_location

			begin
				Phlex::SVG.define_method(:block_given?) { false }

				refute_equal LifecycleIconBlockGiven.instance_method(:view_template).source_location, before
				refute LifecycleIconBlockGiven.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:block_given?)
			ensure
				Phlex::SVG.remove_method(:block_given?)
			end
		end
	end

	test "a component that inlined an svg block is recompiled when what builds or renders Phlex::SVG changes" do
		with_component_files(
			"icon.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIconSetup < Phlex::HTML
					def view_template = svg { |s| s.circle(r: 1) }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleIconSetup)
			inlined = -> { LifecycleIconSetup.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:circle) }
			assert inlined.call

			begin
				Phlex::SVG.define_method(:instance_variable_set) { |*| raise "no blocks" }
				refute inlined.call
				assert_raises(RuntimeError) { LifecycleIconSetup.new.call }
			ensure
				Phlex::SVG.remove_method(:instance_variable_set)
			end

			Phlex::Compiler.recompile(LifecycleIconSetup)
			assert inlined.call

			begin
				Phlex::SVG.__send__(:private, :internal_call)
				refute inlined.call
				assert_raises(NoMethodError) { LifecycleIconSetup.new.call }
			ensure
				Phlex::SVG.remove_method(:internal_call)
			end
		end
	end

	test "an svg block isn't inlined while a core method building Phlex::SVG is replaced" do
		with_component_files(
			"icon.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleIconAllocate < Phlex::HTML
					def view_template = svg { |s| s.circle(r: 1) }
				end
			RUBY
		) do
			Class.class_eval do
				alias_method :__lifecycle_allocate__, :allocate
				def allocate = __lifecycle_allocate__
			end

			Phlex::Compiler.compile(LifecycleIconAllocate)
			refute LifecycleIconAllocate.instance_variable_get(:@__phlex_inlined_svg__)&.include?(:circle)
			assert_equal LifecycleIconAllocate.new.call, %(<svg><circle r="1"></circle></svg>)
		ensure
			Class.class_eval do
				alias_method :allocate, :__lifecycle_allocate__
				remove_method :__lifecycle_allocate__
			end
		end
	end

	test "a class method doesn't recompile what inlined an instance method of the same name" do
		with_component_files(
			"divider.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleDivider < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleDivider)
			assert LifecycleDivider.instance_variable_get(:@__phlex_inlined__).include?(:div)
			before = LifecycleDivider.instance_method(:view_template).source_location

			LifecycleDivider.define_singleton_method(:div) { nil }

			assert_equal LifecycleDivider.instance_method(:view_template).source_location, before
		end
	end

	test "bare whitespace relies on block_given?, which its runtime method asks" do
		with_component_files(
			"whitespace.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleWhitespace < Phlex::HTML
					def view_template = whitespace
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleWhitespace)
			assert_equal LifecycleWhitespace.instance_variable_get(:@__phlex_inlined__), Set[:whitespace, :block_given?]
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
			assert_equal LifecycleFrozenChild.instance_variable_get(:@__phlex_inlined__), Set[:div, :block_given?]

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
			assert_equal LifecycleRefinedElements.instance_variable_get(:@__phlex_inlined__), Set[:section, :block_given?]
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

	test "a block built before rendering reads the state when it's called, and maps its exceptions" do
		with_component_files(
			"early_block.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleEarlyBlock < Phlex::HTML
					def initialize(fail: false)
						@fail = fail
						@footer = footer
					end

					def view_template = div(&@footer)

					private def footer
						proc do
							span { "footer" }
							raise "boom" if @fail
						end
					end
				end
			RUBY
		) do
			assert_equal LifecycleEarlyBlock.new.call, "<div><span>footer</span></div>"

			Phlex::Compiler.compile(LifecycleEarlyBlock)
			assert compiled_method?(LifecycleEarlyBlock, :footer)

			assert_equal LifecycleEarlyBlock.new.call, "<div><span>footer</span></div>"

			error = assert_raises(RuntimeError) { LifecycleEarlyBlock.new(fail: true).call }
			assert_equal error.backtrace.first[/early_block\.rb:(\d+):/, 1], "13"
			refute error.backtrace.any? { |line| line.include?("(compiled") }
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

			with_lazy_compilation do
				assert_equal old.new.call, "<div>gone</div>"
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

	test "precompiling compiles a component as its first render would, reporting a failure rather than raising" do
		with_component_files(
			"precompiled.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecyclePrecompiled < Phlex::HTML
					def view_template = div { "compiled" }
				end
			RUBY
			"precompile_failing.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecyclePrecompileFailing < Phlex::HTML
					def view_template = div { "still works" }
				end
			RUBY
		) do
			with_lazy_compilation { Phlex::Compiler.precompile(LifecyclePrecompiled) }
			assert compiled_method?(LifecyclePrecompiled, :view_template)

			failures = []
			on_failure = -> (component, error) { failures << [component, error.message] }
			with_lazy_compilation do
				Sabotage.active = true
				Phlex::Compiler.precompile(LifecyclePrecompileFailing, on_failure:)
				Phlex::Compiler.precompile(LifecyclePrecompileFailing, on_failure:)
			ensure
				Sabotage.active = false
			end

			refute compiled_method?(LifecyclePrecompileFailing, :view_template)
			assert_equal failures, [[LifecyclePrecompileFailing, "sabotaged"]]
			assert_equal LifecyclePrecompileFailing.new.call, "<div>still works</div>"
		end
	end

	test "forgetting an unloaded component drops its compiled source maps and failures" do
		with_component_files(
			"forgotten.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleForgotten < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			"forgotten_failing.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleForgottenFailing < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
		) do
			forgotten = LifecycleForgotten
			Phlex::Compiler.compile(forgotten)
			compiled_path = forgotten.instance_method(:view_template).source_location[0]
			assert Phlex.__compiled_source_maps__.key?(compiled_path)

			failing = LifecycleForgottenFailing
			with_lazy_compilation do
				Sabotage.active = true
				Phlex::Compiler.precompile(failing, on_failure: -> (*) {})
			ensure
				Sabotage.active = false
			end
			assert Phlex::Compiler::FAILURES.key?(failing)

			Object.__send__(:remove_const, :LifecycleForgotten)
			Object.__send__(:remove_const, :LifecycleForgottenFailing)
			Phlex::Compiler.forget(forgotten)
			Phlex::Compiler.forget(failing)

			refute Phlex.__compiled_source_maps__.key?(compiled_path)
			refute Phlex::Compiler::FAILURES.key?(failing)
		end
	end

	test "forgetting an unloaded component keeps source maps another live component still uses" do
		with_component_files(
			"shared.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSharedGone < Phlex::HTML
					def view_template = div { "gone" }
				end

				class LifecycleSharedLive < Phlex::HTML
					def view_template = div { "live" }
				end
			RUBY
		) do
			gone = LifecycleSharedGone
			live = LifecycleSharedLive
			Phlex::Compiler.compile_file(gone.instance_method(:view_template).source_location[0], components: [gone, live])
			compiled_path = live.instance_method(:view_template).source_location[0]
			assert_equal gone.instance_method(:view_template).source_location[0], compiled_path

			Object.__send__(:remove_const, :LifecycleSharedGone)
			Phlex::Compiler.forget(gone)
			assert Phlex.__compiled_source_maps__.key?(compiled_path)

			Object.__send__(:remove_const, :LifecycleSharedLive)
			Phlex::Compiler.forget(live)
			refute Phlex.__compiled_source_maps__.key?(compiled_path)
		end
	end

	test "forgetting a recompiled component drops every generation it was compiled into" do
		with_component_files(
			"recompiled.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleRecompiledGone < Phlex::HTML
					def view_template = div { "gone" }
				end
			RUBY
		) do
			component = LifecycleRecompiledGone
			Phlex::Compiler.compile(component)
			first = component.instance_method(:view_template).source_location[0]
			Phlex::Compiler.recompile(component)
			second = component.instance_method(:view_template).source_location[0]
			refute_equal first, second

			Object.__send__(:remove_const, :LifecycleRecompiledGone)
			Phlex::Compiler.forget(component)

			refute Phlex.__compiled_source_maps__.key?(first)
			refute Phlex.__compiled_source_maps__.key?(second)
		end
	end

	test "forgetting a component keeps the source maps its live subclasses inherit" do
		with_component_files(
			"inherited.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleForgottenParent < Phlex::HTML
					def view_template = div { "inherited" }
				end

				class LifecycleLiveChild < LifecycleForgottenParent
				end
			RUBY
		) do
			parent = LifecycleForgottenParent
			Phlex::Compiler.compile(parent)
			compiled_path = parent.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleForgottenParent)
			Phlex::Compiler.forget(parent)

			assert Phlex.__compiled_source_maps__.key?(compiled_path)
		end
	end

	test "forgetting a component that shares a generation stops the compiler holding on to it" do
		with_component_files(
			"released.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleReleased < Phlex::HTML
					def view_template = div { "released" }
				end

				class LifecycleSharedKept < Phlex::HTML
					def view_template = div { "kept" }
				end
			RUBY
		) do
			released = LifecycleReleased
			kept = LifecycleSharedKept
			Phlex::Compiler.compile_file(released.instance_method(:view_template).source_location[0], components: [released, kept])
			compiled_path = kept.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleReleased)
			Phlex::Compiler.forget(released)

			assert_equal Phlex::Compiler::GENERATION_COMPONENTS[compiled_path].keys, [kept]
		end
	end

	test "forgetting the last subclass releases the source maps its forgotten parent kept" do
		with_component_files(
			"deferred.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleDeferredParent < Phlex::HTML
					def view_template = div { "deferred" }
				end

				class LifecycleDeferredChild < LifecycleDeferredParent
				end
			RUBY
		) do
			parent = LifecycleDeferredParent
			child = LifecycleDeferredChild
			Phlex::Compiler.compile(parent)
			compiled_path = parent.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleDeferredParent)
			Phlex::Compiler.forget(parent)
			assert Phlex.__compiled_source_maps__.key?(compiled_path)

			Object.__send__(:remove_const, :LifecycleDeferredChild)
			Phlex::Compiler.forget(child)
			refute Phlex.__compiled_source_maps__.key?(compiled_path)
			refute Phlex::Compiler::GENERATION_COMPONENTS.key?(compiled_path)
		end
	end

	test "forgetting a component keeps a shared generation another owner's live subclass inherits" do
		with_component_files(
			"shared_inherited.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSharedForgotten < Phlex::HTML
					def view_template = div { "forgotten" }
				end

				class LifecycleSharedParent < Phlex::HTML
					def view_template = div { "parent" }
				end

				class LifecycleSharedChild < LifecycleSharedParent
				end
			RUBY
		) do
			forgotten = LifecycleSharedForgotten
			parent = LifecycleSharedParent
			Phlex::Compiler.compile_file(parent.instance_method(:view_template).source_location[0], components: [forgotten, parent])
			compiled_path = parent.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleSharedParent)
			Object.__send__(:remove_const, :LifecycleSharedForgotten)
			Phlex::Compiler.forget(forgotten)

			assert Phlex.__compiled_source_maps__.key?(compiled_path)
			assert_equal Phlex::Compiler::GENERATION_COMPONENTS[compiled_path].keys, [parent]
		end
	end

	test "forgetting components doesn't autoload what replaced them" do
		with_component_files(
			"autoloaded.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleAutoloadedGone < Phlex::HTML
					def view_template = div { "gone" }
				end

				class LifecycleAutoloadedOther < Phlex::HTML
					def view_template = div { "other" }
				end
			RUBY
			"replacement.rb" => <<~RUBY
				# frozen_string_literal: true
				$lifecycle_replacement_loaded = true
			RUBY
		) do |(path, replacement)|
			gone = LifecycleAutoloadedGone
			other = LifecycleAutoloadedOther
			Phlex::Compiler.compile_file(path, components: [gone, other])
			$lifecycle_replacement_loaded = false

			Object.__send__(:remove_const, :LifecycleAutoloadedGone)
			Object.__send__(:remove_const, :LifecycleAutoloadedOther)
			Object.autoload(:LifecycleAutoloadedGone, replacement)
			Object.autoload(:LifecycleAutoloadedOther, replacement)
			Phlex::Compiler.forget(gone, other)

			refute $lifecycle_replacement_loaded
			refute Phlex::Compiler::GENERATION_COMPONENTS.key?(other.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :LifecycleAutoloadedGone) if Object.autoload?(:LifecycleAutoloadedGone)
			Object.__send__(:remove_const, :LifecycleAutoloadedOther) if Object.autoload?(:LifecycleAutoloadedOther)
		end
	end

	test "forgetting a component keeps the source maps of another unloaded component that isn't forgotten yet" do
		with_component_files(
			"first.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleFirstGone < Phlex::HTML
					def view_template = div { "first" }
				end
			RUBY
			"second.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSecondGone < Phlex::HTML
					def view_template = div { "second" }
				end
			RUBY
		) do
			first = LifecycleFirstGone
			second = LifecycleSecondGone
			Phlex::Compiler.compile(first)
			Phlex::Compiler.compile(second)
			compiled_path = second.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleFirstGone)
			Object.__send__(:remove_const, :LifecycleSecondGone)
			Phlex::Compiler.forget(first)
			assert Phlex.__compiled_source_maps__.key?(compiled_path)

			Phlex::Compiler.forget(second)
			refute Phlex.__compiled_source_maps__.key?(compiled_path)
		end
	end

	test "forgetting a component keeps the source maps an anonymous subclass inherits" do
		with_component_files(
			"anonymous_parent.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleAnonymousParent < Phlex::HTML
					def view_template = div { "inherited" }
				end
			RUBY
		) do
			parent = LifecycleAnonymousParent
			child = Class.new(parent)
			Phlex::Compiler.compile(parent)
			compiled_path = parent.instance_method(:view_template).source_location[0]

			Object.__send__(:remove_const, :LifecycleAnonymousParent)
			Phlex::Compiler.forget(parent)
			assert Phlex.__compiled_source_maps__.key?(compiled_path)

			Phlex::Compiler.forget(child)
			refute Phlex.__compiled_source_maps__.key?(compiled_path)
		end
	end

	test "an ancestor that can't be compiled is reported once, not again for each subclass" do
		with_component_files(
			"failing_parent.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleFailingParent < Phlex::HTML
					def view_template = delegate("parent")

					ruby2_keywords def delegate(*args) = div { plain(*args) }
				end

				class LifecycleFailingFirst < LifecycleFailingParent
					def view_template = span { "first" }
				end

				class LifecycleFailingSecond < LifecycleFailingParent
					def view_template = span { "second" }
				end
			RUBY
		) do
			reports = []
			on_failure = -> (component, _error) { reports << component }

			with_lazy_compilation do
				Phlex::Compiler.precompile(LifecycleFailingFirst, on_failure:)
				Phlex::Compiler.precompile(LifecycleFailingSecond, on_failure:)
				3.times { Phlex::Compiler.precompile(Class.new(LifecycleFailingParent), on_failure:) }
			end

			assert_equal reports, [LifecycleFailingFirst]
			assert compiled_method?(LifecycleFailingSecond, :view_template)
			assert_equal LifecycleFailingSecond.new.call, "<span>second</span>"
			assert_equal Phlex::Compiler.explain(LifecycleFailingFirst).map(&:message).grep(/\Acompiling/), ["compiling LifecycleFailingParent raised Phlex::Compiler::Error: #{Phlex::Compiler::FAILURES[LifecycleFailingParent].message}"]
		end
	end

	test "running out of stack while compiling is reported, and the component renders uncompiled" do
		with_component_files(
			"stack.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleStack < Phlex::HTML
					def view_template = div { "stack" }
				end
			RUBY
		) do
			failures = []

			with_lazy_compilation do
				Sabotage.active = SystemStackError
				Phlex::Compiler.precompile(LifecycleStack, on_failure: -> (component, error) { failures << [component, error.class] })
			ensure
				Sabotage.active = false
			end

			assert_equal failures, [[LifecycleStack, SystemStackError]]
			assert_equal LifecycleStack.new.call, "<div>stack</div>"
		end
	end

	test "a class overriding name doesn't change which component the compiler compiles" do
		with_component_files(
			"named.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleNamedBase < Phlex::HTML
					def self.name = "LifecycleNamedBase"

					def view_template = div { "base" }
				end

				class LifecycleNamedSub < LifecycleNamedBase
					def view_template = span { "sub" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleNamedSub)

			assert compiled_method?(LifecycleNamedSub, :view_template)
		end
	end

	test "a component loaded while another compiles, and precompiled as it loads, waits for its first render" do
		with_component_files(
			"outer.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecycleOuter < Phlex::HTML
					def view_template = div { "outer" }
				end
			RUBY
			"inner.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleInner < Phlex::HTML
					def view_template = span { "inner" }
				end
			RUBY
		) do
			failures = []
			on_failure = -> (component, error) { failures << [component, error.class] }

			with_lazy_compilation do
				Pause.gate = -> { Phlex::Compiler.precompile(LifecycleInner, on_failure:) }
				Phlex::Compiler.precompile(LifecycleOuter, on_failure:)
			ensure
				Pause.gate = nil
			end

			assert_equal failures, []
			assert compiled_method?(LifecycleOuter, :view_template)
			refute compiled_method?(LifecycleInner, :view_template)

			with_lazy_compilation { assert_equal LifecycleInner.new.call, "<span>inner</span>" }
			assert compiled_method?(LifecycleInner, :view_template)
		end
	end

	test "a subclass whose own file compiled is marked compiled when its parent's file fails" do
		with_component_files(
			"partial_parent.rb" => <<~RUBY,
				# frozen_string_literal: true
				class LifecyclePartialParent < Phlex::HTML
					def view_template = delegate("parent")

					ruby2_keywords def delegate(*args) = div { plain(*args) }
				end
			RUBY
			"partial_child.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecyclePartialChild < LifecyclePartialParent
					def view_template = div { "child" }
				end
			RUBY
		) do
			reports = []

			with_lazy_compilation do
				Phlex::Compiler.precompile(LifecyclePartialChild, on_failure: -> (component, _error) { reports << component })
			end

			assert_equal reports, [LifecyclePartialChild]
			assert compiled_method?(LifecyclePartialChild, :view_template)
			assert Phlex::Compiler.compiled?(LifecyclePartialChild)
			refute Phlex::Compiler.compiled?(LifecyclePartialParent)
			assert Phlex::Compiler::FAILURES.key?(LifecyclePartialParent)
			refute Phlex::Compiler::FAILURES.key?(LifecyclePartialChild)

			LifecyclePartialChild.freeze
			LifecyclePartialParent.class_eval { def div(**, &) = super(class: "redefined", &) }
			assert_equal LifecyclePartialChild.new.call, %(<div class="redefined">child</div>)
		end
	end

	test "the compiler doesn't keep unloaded components alive when nothing forgets them" do
		skip "Needs a precise garbage collector" unless RUBY_ENGINE == "ruby"

		Dir.mktmpdir do |dir|
			path = File.join(dir, "collected.rb")
			File.write(path, <<~RUBY)
				# frozen_string_literal: true
				class LifecycleCollected < Phlex::HTML
					def view_template = div { "collected" }
				end
			RUBY

			references = 10.times.map do
				load path
				Phlex::Compiler.compile(LifecycleCollected)
				reference = WeakRef.new(LifecycleCollected)
				Object.__send__(:remove_const, :LifecycleCollected)
				reference
			end

			GC.start(full_mark: true, immediate_sweep: true)

			assert references.count(&:weakref_alive?) < 10
		end
	end

	# Pauses a thread that sets :lifecycle_install_gate just before compiled methods are installed.
	module InstallPause
		def without_redefinition_warnings(&)
			Thread.current[:lifecycle_install_gate]&.call
			super
		end
	end

	Phlex::Compiler.singleton_class.prepend(InstallPause)

	test "a subclass defined while its parent compiles sees its override honoured" do
		Dir.mktmpdir do |dir|
			parent_path = File.join(dir, "race_parent.rb")
			child_path = File.join(dir, "race_child.rb")
			File.write(parent_path, <<~RUBY)
				# frozen_string_literal: true
				class LifecycleRaceParent < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			File.write(child_path, <<~RUBY)
				# frozen_string_literal: true
				class LifecycleRaceChild < LifecycleRaceParent
					def div(**, &) = super(class: "child", **, &)
				end
			RUBY
			load parent_path

			paused = Queue.new
			resume = Queue.new
			compiling = Thread.new do
				Thread.current[:lifecycle_install_gate] = -> {
					Thread.current[:lifecycle_install_gate] = nil
					paused << true
					resume.pop
				}
				Phlex::Compiler.compile(LifecycleRaceParent)
			end

			compiling.join unless paused.pop(timeout: 5)
			defining = Thread.new { load child_path }
			Thread.pass until defining.stop?
			resume << true
			compiling.join
			defining.join

			assert_equal LifecycleRaceChild.new.call, %(<div class="child">x</div>)
		end
	end

	test "a class overriding instance variable reflection doesn't change its compile setting" do
		component = Class.new(Phlex::HTML) do
			compile false

			def self.instance_variable_defined?(*) = false
			def self.instance_variable_get(*) = true
		end

		refute component.compile?
	end

	test "a class overriding instance variable reflection is still compiled on its first render" do
		with_component_files(
			"reflective.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleReflective < Phlex::HTML
					def self.instance_variable_get(*) = true
					def self.instance_variable_set(*) = nil
					def self.instance_variable_defined?(*) = false

					def view_template = div { "reflective" }
				end
			RUBY
		) do
			with_lazy_compilation do
				assert_equal LifecycleReflective.new.call, "<div>reflective</div>"
				assert compiled_method?(LifecycleReflective, :view_template)
				assert Phlex::Compiler.compiled?(LifecycleReflective)
			end
		end
	end

	test "a namespace overriding constant reflection doesn't hide a loaded component" do
		with_component_files(
			"namespaced.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSecretive
					def self.const_defined?(*) = false
					def self.autoload?(*) = "elsewhere"
					def self.const_get(*) = nil

					class Hidden < Phlex::HTML
						def view_template = div { "hidden" }
					end
				end
			RUBY
		) do
			component = LifecycleSecretive::Hidden

			error = assert_raises(ArgumentError) { Phlex::Compiler.forget(component) }
			assert_equal error.message, "Can't forget LifecycleSecretive::Hidden because it's still loaded."
		end
	end

	test "a component defining its own compile? still compiles as its setting says" do
		with_component_files(
			"own_compile.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleOwnCompile < Phlex::HTML
					def self.compile? = raise("not Phlex's")

					def view_template = div { "own" }
				end
			RUBY
		) do
			with_lazy_compilation { assert_equal LifecycleOwnCompile.new.call, "<div>own</div>" }

			assert compiled_method?(LifecycleOwnCompile, :view_template)
		end
	end

	test "a live component can't be forgotten" do
		with_component_files(
			"remembered.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleRemembered < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleRemembered)

			error = assert_raises(ArgumentError) { Phlex::Compiler.forget(LifecycleRemembered) }
			assert_equal error.message, "Can't forget LifecycleRemembered because it's still loaded."
		end
	end

	test "a component compiles on its first render unless its class or an ancestor says compile false" do
		with_component_files(
			"settings.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleDefault < Phlex::HTML
					def view_template = div { "default" }
				end

				class LifecycleOptedOut < Phlex::HTML
					compile false

					def view_template = div { "opted out" }
				end

				class LifecycleInheritsOptOut < LifecycleOptedOut
					def view_template = div { "inherits" }
				end

				class LifecycleOptsBackIn < LifecycleOptedOut
					compile true

					def view_template = div { "back in" }
				end
			RUBY
		) do
			assert LifecycleDefault.compile?
			refute LifecycleOptedOut.compile?
			refute LifecycleInheritsOptOut.compile?
			assert LifecycleOptsBackIn.compile?

			with_lazy_compilation do
				assert_equal LifecycleDefault.call, "<div>default</div>"
				assert_equal LifecycleOptedOut.call, "<div>opted out</div>"
				assert_equal LifecycleInheritsOptOut.call, "<div>inherits</div>"
				assert_equal LifecycleOptsBackIn.call, "<div>back in</div>"
			end

			assert compiled_method?(LifecycleDefault, :view_template)
			refute compiled_method?(LifecycleOptedOut, :view_template)
			refute compiled_method?(LifecycleInheritsOptOut, :view_template)
			assert compiled_method?(LifecycleOptsBackIn, :view_template)
		end
	end

	test "compile only takes true or false" do
		error = assert_raises(Phlex::ArgumentError) { Class.new(Phlex::HTML) { compile :yes } }
		assert_equal error.message, "Expected compile to be true or false, got :yes."
	end

	test "disabling the compiler stops components compiling on first render, whatever they say" do
		with_component_files(
			"disabled.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleDisabled < Phlex::HTML
					compile true

					def view_template = div { "disabled" }
				end
			RUBY
		) do
			with_lazy_compilation do
				Phlex::Compiler.disable!
				assert_equal LifecycleDisabled.call, "<div>disabled</div>"
				Phlex::Compiler.precompile(LifecycleDisabled)
			end

			refute compiled_method?(LifecycleDisabled, :view_template)
		end
	end

	test "source returns the Ruby a component compiles to, without compiling it" do
		with_component_files(
			"source.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSource < Phlex::HTML
					def view_template = div(class: "card") { "source" }

					def helper = "not compiled"

					private def item = span { "item" }
				end
			RUBY
		) do |(path)|
			source = Phlex::Compiler.source(LifecycleSource)

			refute compiled_method?(LifecycleSource, :view_template)
			assert source.start_with?("# -*- coding: UTF-8; frozen_string_literal: true -*-\n# #{path}\n")
			assert source.include?("private(:item)\n")
			assert source.include?("class LifecycleSource")
			assert source.include?("def view_template")
			assert source.include?(%(<div class="card">source</div>))
			refute source.include?("def helper")

			Phlex::Compiler.compile(LifecycleSource)
			assert_equal Phlex::Compiler.source(LifecycleSource), source
		end
	end

	test "source declares visibility inside the class, so it evaluates for a private constant" do
		with_component_files(
			"private_constant.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSourceNamespace
					class Hidden < Phlex::HTML
						def view_template = item

						private def item = span { "hidden" }
					end

					private_constant :Hidden

					def self.render = Hidden.new.call
				end
			RUBY
		) do
			component = LifecycleSourceNamespace.const_get(:Hidden)
			source = Phlex::Compiler.source(component)

			eval(source, TOPLEVEL_BINDING.dup, "(source)", 1)

			assert component.private_method_defined?(:item)
			assert_equal LifecycleSourceNamespace.render, "<span>hidden</span>"
		end
	end

	test "source is empty when nothing would be compiled" do
		with_component_files(
			"nothing.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleNothingToSource < Phlex::HTML
					def label = "plain Ruby"
				end
			RUBY
		) do
			assert_equal Phlex::Compiler.source(LifecycleNothingToSource), ""
		end
	end

	test "a frozen component renders without waiting for another component compiling" do
		with_component_files(
			"frozen.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleFrozen < Phlex::HTML
					def view_template = div { "frozen" }
				end
			RUBY
		) do
			LifecycleFrozen.freeze

			with_lazy_compilation do
				locked = Queue.new
				release = Queue.new
				compiling = Thread.new do
					Phlex::Compiler::MUTEX.synchronize do
						locked << true
						release.pop
					end
				end
				locked.pop

				render = Thread.new { LifecycleFrozen.call }
				finished = render.join(2)
				release << true

				assert finished
				assert_equal render.value, "<div>frozen</div>"
				compiling.join
			ensure
				release&.<< true
			end
		end
	end

	test "a component that says compile false waits for a recompilation of the methods it inherits" do
		with_component_files(
			"inherits.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleRecompiledParent < Phlex::HTML
					def view_template = div { "inherited" }
				end

				class LifecycleUncompiledChild < LifecycleRecompiledParent
					compile false
				end
			RUBY
		) do
			with_lazy_compilation do
				Phlex::Compiler.compile(LifecycleRecompiledParent)

				locked = Queue.new
				release = Queue.new
				Pause.gate = -> {
					Pause.gate = nil
					locked << true
					release.pop
				}
				recompiling = Thread.new { Phlex::Compiler.recompile(LifecycleRecompiledParent) }
				locked.pop

				render = Thread.new { LifecycleUncompiledChild.call }
				deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
				Thread.pass until render.status == "sleep" || !render.alive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

				assert render.alive?
				release << true
				assert_equal render.value, "<div>inherited</div>"
				recompiling.join
			ensure
				Pause.gate = nil
				release&.<< true
			end
		end
	end

	test "a class overriding superclass still reads its inherited compile setting" do
		component = Class.new(Phlex::HTML) do
			compile false

			def self.superclass = nil
		end

		child = Class.new(component) do
			def self.superclass = self
		end

		refute child.compile?
	end

	test "super from an override of an element is compiled as the element" do
		with_component_files(
			"super.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSuper < Phlex::HTML
					def view_template = h1(id: "title") { yielded_by_element? ? "element" : "compiled" }

					def h1(**attrs, &)
						super(**mix(attrs, class: "font-bold"), &)
					end

					def yielded_by_element? = caller_locations.any? { |location| location.path == Phlex::Compiler::Environment::ELEMENTS_SOURCE_PATH }
				end
			RUBY
		) do
			without_lazy_compilation { assert_equal LifecycleSuper.new.call, %(<h1 id="title" class="font-bold">element</h1>) }

			Phlex::Compiler.compile(LifecycleSuper)
			assert compiled_method?(LifecycleSuper, :h1)
			assert_equal LifecycleSuper.instance_variable_get(:@__phlex_inlined_super__), Set[:h1]
			assert_equal LifecycleSuper.new.call, %(<h1 id="title" class="font-bold">compiled</h1>)
		end
	end

	test "a module mixed in under an override whose super was compiled takes effect" do
		with_component_files(
			"super_included.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSuperIncluded < Phlex::HTML
					def view_template = h1 { "Hello" }
					def h1(**, &) = super
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleSuperIncluded)
			assert_equal LifecycleSuperIncluded.new.call, "<h1>Hello</h1>"

			LifecycleSuperIncluded.include(Module.new { def h1(**, &) = plain("included h1") })
			assert_equal LifecycleSuperIncluded.new.call, "included h1"
		end
	end

	test "overriding an element whose super was compiled, on an instance or a subclass, leaves the compiled override alone" do
		with_component_files(
			"super_overridden.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleSuperOverridden < Phlex::HTML
					def view_template = h1 { "Hello" }
					def h1(**, &) = super(class: "x", &)
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleSuperOverridden)
			location = LifecycleSuperOverridden.instance_method(:h1).source_location

			instance = LifecycleSuperOverridden.new
			instance.define_singleton_method(:h1) { |**, &block| span { super(&block) } }
			assert_equal instance.call, %(<span><h1 class="x">Hello</h1></span>)

			Class.new(LifecycleSuperOverridden) { def h1(**, &) = plain("subclass") }
			assert_equal LifecycleSuperOverridden.instance_method(:h1).source_location, location
		end
	end
end
