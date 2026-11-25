# frozen_string_literal: true

require "tmpdir"
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
			raise "sabotaged" if Sabotage.active

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
				end
			RUBY
		) do |(path)|
			source = Phlex::Compiler.source(LifecycleSource)

			refute compiled_method?(LifecycleSource, :view_template)
			assert source.start_with?("# #{path}\n")
			assert source.include?("class LifecycleSource")
			assert source.include?("def view_template")
			assert source.include?(%(<div class="card">source</div>))
			refute source.include?("def helper")

			Phlex::Compiler.compile(LifecycleSource)
			assert_equal Phlex::Compiler.source(LifecycleSource), source
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
end
