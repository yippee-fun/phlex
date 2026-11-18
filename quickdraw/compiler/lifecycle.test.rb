# frozen_string_literal: true

require "tmpdir"

class CompilerLifecycleTest < Quickdraw::Test
	Phlex::Compiler

	def compiled_method?(component, name)
		Phlex.__compiled_source_maps__.key?(component.instance_method(name).source_location[0])
	end

	def generations_of(path)
		Phlex.__compiled_source_maps__.each_value.count { |generation| generation.path == path }
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
			Phlex::Compiler.enable!
			begin
				LifecycleWaits.call
				assert Phlex::Compiler.compiled?(LifecycleWaits)

				locked = Queue.new
				release = Queue.new
				recompiling = Thread.new do
					Phlex::Compiler::MUTEX.synchronize do
						locked << true
						release.pop
					end
				end
				locked.pop

				render = Thread.new { LifecycleWaits.call }
				deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
				Thread.pass until render.status == "sleep" || !render.alive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

				assert render.alive?
				release << true
				assert_equal render.value, "<div>waits</div>"
				recompiling.join
			ensure
				release&.<< true
				Phlex::Compiler.disable!
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

	# Runs a block on another thread once a method's calls have been resolved,
	# standing in for a change made while compiling.
	module Interleave
		def self.pending = @pending

		def self.pending=(pending)
			@pending = pending
		end

		def compile(node, **)
			result = super

			if (pending = Interleave.pending)
				Interleave.pending = nil
				Thread.new(&pending).join
			end

			result
		end
	end

	Phlex::Compiler::MethodCompiler.prepend(Interleave)

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

	test "a module with a frozen singleton class mixed in later is refused before it's mixed in" do
		with_component_files(
			"frozen_later.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleFrozenLaterHelpers
				end

				class LifecycleFrozenLater < Phlex::HTML
					include LifecycleFrozenLaterHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleFrozenLater)

			frozen = Module.new
			frozen.singleton_class.freeze

			assert_raises(Phlex::Compiler::Error) { LifecycleFrozenLater.include(frozen) }
			assert_raises(Phlex::Compiler::Error) { LifecycleFrozenLaterHelpers.include(frozen) }
			refute LifecycleFrozenLater.include?(frozen)
		end
	end

	test "the modules an overridden include actually adds are watched" do
		with_component_files(
			"substituting.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSubstitute
				end

				module LifecycleSubstituting
					def self.include(*) = super(LifecycleSubstitute)
				end

				class LifecycleSubstitutingComponent < Phlex::HTML
					include LifecycleSubstituting

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleSubstitutingComponent)

			LifecycleSubstituting.include(Module.new)
			LifecycleSubstitute.define_method(:div) { |**| plain("substitute div") }
			assert_equal LifecycleSubstitutingComponent.new.call, "substitute div"
		end
	end

	test "an element registered again with a new tag takes effect" do
		with_component_files(
			"reregistered.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleRegisteredElements
					extend Phlex::SGML::Elements

					register_element :lifecycle_widget
				end

				class LifecycleReregistered < Phlex::HTML
					include LifecycleRegisteredElements

					register_element :lifecycle_gadget

					def view_template
						lifecycle_widget { "x" }
						lifecycle_gadget { "y" }
					end
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleReregistered)
			assert_equal LifecycleReregistered.new.call, "<lifecycle-widget>x</lifecycle-widget><lifecycle-gadget>y</lifecycle-gadget>"

			LifecycleRegisteredElements.register_element :lifecycle_widget, tag: "new-widget"
			LifecycleReregistered.register_element :lifecycle_gadget, tag: "new-gadget"
			assert_equal LifecycleReregistered.new.call, "<new-widget>x</new-widget><new-gadget>y</new-gadget>"
			assert compiled_method?(LifecycleReregistered, :view_template)
		end
	end

	test "a module included only into a subclass is watched when its parent is compiled" do
		with_component_files(
			"subclass_mixin.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSubclassOnlyHelpers
				end

				class LifecycleSubclassMixinParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleSubclassMixinChild < LifecycleSubclassMixinParent
					include LifecycleSubclassOnlyHelpers
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleSubclassMixinChild)

			LifecycleSubclassOnlyHelpers.define_method(:div) { |**| plain("subclass helper div") }
			assert_equal LifecycleSubclassMixinChild.new.call, "subclass helper div"
			assert_equal LifecycleSubclassMixinParent.new.call, "<div>x</div>"
		end
	end

	test "prepending a module already further up the ancestry takes effect" do
		with_component_files(
			"reprepended.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleReprependedHelpers
					def lifecycle_badge(**) = plain("helper badge")
				end

				class LifecycleReprependedParent < Phlex::HTML
					include LifecycleReprependedHelpers
				end

				class LifecycleReprepended < LifecycleReprependedParent
					register_element :lifecycle_badge

					def view_template = lifecycle_badge { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleReprepended)
			assert_equal LifecycleReprepended.new.call, "<lifecycle-badge>x</lifecycle-badge>"

			LifecycleReprepended.prepend(LifecycleReprependedHelpers)

			# TruffleRuby leaves a module already further up where it is.
			if LifecycleReprepended.ancestors.first == LifecycleReprependedHelpers
				assert_equal LifecycleReprepended.new.call, "helper badge"
			else
				assert_equal LifecycleReprepended.new.call, "<lifecycle-badge>x</lifecycle-badge>"
			end
		end
	end

	test "a module that can't be watched, added in place of the one given, leaves nothing inlined" do
		with_component_files(
			"substituted_frozen.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleFrozenSubstitute
				end
				LifecycleFrozenSubstitute.singleton_class.freeze

				module LifecycleFrozenSubstituting
					def self.include(*) = super(LifecycleFrozenSubstitute)
				end

				class LifecycleFrozenSubstitutingComponent < Phlex::HTML
					include LifecycleFrozenSubstituting

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleFrozenSubstitutingComponent)
			assert compiled_method?(LifecycleFrozenSubstitutingComponent, :view_template)

			assert_raises(Phlex::Compiler::Error) { LifecycleFrozenSubstituting.include(Module.new) }
			refute Phlex::Compiler.inlines?(LifecycleFrozenSubstitutingComponent)

			LifecycleFrozenSubstitute.define_method(:div) { |**| plain("substitute div") }
			assert_equal LifecycleFrozenSubstitutingComponent.new.call, "substitute div"
		end
	end

	test "a module changed on another thread while compiling takes effect" do
		with_component_files(
			"concurrent.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleConcurrentHelpers
				end

				class LifecycleConcurrent < Phlex::HTML
					include LifecycleConcurrentHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do
			Interleave.pending = -> { LifecycleConcurrentHelpers.define_method(:div) { |**| plain("concurrent div") } }
			Phlex::Compiler.compile(LifecycleConcurrent)

			assert_equal LifecycleConcurrent.new.call, "concurrent div"
		ensure
			Interleave.pending = nil
		end
	end

	test "an unrelated change on another thread while compiling doesn't compile again" do
		with_component_files(
			"concurrent_unrelated.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleConcurrentUnrelated < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleConcurrentBystander < Phlex::HTML
				end
			RUBY
		) do |(path)|
			Interleave.pending = lambda do
				LifecycleConcurrentBystander.define_method(:div) { |**| plain("bystander div") }
				LifecycleConcurrentBystander.define_method(:helper) { nil }
			end

			Phlex::Compiler.compile(LifecycleConcurrentUnrelated)

			assert_equal generations_of(path), 1
			assert_equal LifecycleConcurrentUnrelated.new.call, "<div>x</div>"
		ensure
			Interleave.pending = nil
		end
	end

	test "an included module that undefines an inlined element takes effect" do
		with_component_files(
			"hidden.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleHidden < Phlex::HTML
					def view_template = div { "x" }
				end

				module LifecycleHides
					def div = nil
					undef_method :div
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleHidden)
			assert_equal LifecycleHidden.new.call, "<div>x</div>"

			LifecycleHidden.include(LifecycleHides)
			assert_raises(NoMethodError) { LifecycleHidden.new.call }
		end
	end

	test "a module that undefines an inlined element, included into a subclass, takes effect there" do
		with_component_files(
			"hidden_below.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleHiddenParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleHiddenChild < LifecycleHiddenParent
					def helper = span { "y" }
				end

				module LifecycleHidesBelow
					def div = nil
					undef_method :div
				end
			RUBY
		) do |(path)|
			Phlex::Compiler.compile(LifecycleHiddenChild)
			assert_equal LifecycleHiddenChild.new.call, "<div>x</div>"

			# The child's own helper doesn't resolve in the parent, which isn't
			# a reason to compile anything again.
			LifecycleHiddenParent.include(Module.new)
			assert_equal generations_of(path), 1

			LifecycleHiddenChild.include(LifecycleHidesBelow)
			assert_raises(NoMethodError) { LifecycleHiddenChild.new.call }
			assert_equal LifecycleHiddenParent.new.call, "<div>x</div>"
		end
	end

	test "a module that undefines an element, included on another thread while compiling, takes effect" do
		with_component_files(
			"hidden_concurrently.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleHiddenConcurrently < Phlex::HTML
					def view_template = div { "x" }
				end

				module LifecycleHidesConcurrently
					def div = nil
					undef_method :div
				end
			RUBY
		) do
			Interleave.pending = -> { LifecycleHiddenConcurrently.include(LifecycleHidesConcurrently) }
			Phlex::Compiler.compile(LifecycleHiddenConcurrently)

			assert_raises(NoMethodError) { LifecycleHiddenConcurrently.new.call }
		ensure
			Interleave.pending = nil
		end
	end

	test "a change that can't be compiled for is refused every time" do
		with_component_files(
			"unrecompilable.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleUnrecompilableHelpers
				end

				class LifecycleUnrecompilable < Phlex::HTML
					include LifecycleUnrecompilableHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do |(path)|
			Phlex::Compiler.compile(LifecycleUnrecompilable)
			File.write(path, "\n#{File.read(path)}")

			2.times do
				error = assert_raises(Phlex::Compiler::Error) do
					LifecycleUnrecompilableHelpers.define_method(:div) { |**| plain("helper div") }
				end

				assert error.message.include?("changed since it was loaded")
			end
		end
	end

	test "a watched module's own include still receives keywords" do
		with_component_files(
			"keywords.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleKeywords
					def self.include(*modules, validate: true)
						super(*modules)
						validate
					end
				end

				class LifecycleKeywordsComponent < Phlex::HTML
					include LifecycleKeywords

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleKeywordsComponent)

			assert LifecycleKeywords.singleton_class < Phlex::Compiler::MixinHooks
			assert_equal LifecycleKeywords.include(Module.new, validate: false), false
		end
	end

	test "modules overriding frozen? and ancestors are still watched" do
		with_component_files(
			"overriding.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleClaimsFrozen
					def self.frozen? = true
				end

				module LifecycleHidesAncestors
					def self.ancestors = [self]
				end

				class LifecycleOverriding < Phlex::HTML
					include LifecycleClaimsFrozen
					include LifecycleHidesAncestors

					def view_template
						div { "x" }
						span { "y" }
					end
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleOverriding)

			LifecycleClaimsFrozen.define_method(:div) { |**| plain("unfrozen div") }
			assert_equal LifecycleOverriding.new.call, "unfrozen div<span>y</span>"

			hidden = Module.new
			LifecycleHidesAncestors.include(hidden)
			hidden.define_method(:span) { |**| plain("hidden span") }
			assert_equal LifecycleOverriding.new.call, "unfrozen divhidden span"
		end
	end

	test "a module mixed in by an include that then raises is still watched" do
		with_component_files(
			"raising.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleRaisingHelpers
				end

				class LifecycleRaising < Phlex::HTML
					include LifecycleRaisingHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleRaising)

			refusing = Module.new { def self.included(*) = raise("refused") }
			assert_raises(RuntimeError) { LifecycleRaisingHelpers.include(refusing) }
			assert LifecycleRaisingHelpers.include?(refusing)

			refusing.define_method(:div) { |**| plain("refusing div") }
			assert_equal LifecycleRaising.new.call, "refusing div"
		end
	end

	test "a watched module's private include stays private" do
		with_component_files(
			"private_include.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecyclePrivateInclude
					private_class_method :include
				end

				class LifecyclePrivateIncludeComponent < Phlex::HTML
					include LifecyclePrivateInclude

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecyclePrivateIncludeComponent)

			assert LifecyclePrivateInclude.singleton_class < Phlex::Compiler::MixinHooks
			assert_raises(NoMethodError) { LifecyclePrivateInclude.include(Module.new) }
			assert LifecyclePrivateInclude.respond_to?(:prepend)

			hidden = Module.new
			LifecyclePrivateInclude.__send__(:include, hidden)
			hidden.define_method(:div) { |**| plain("hidden div") }
			assert_equal LifecyclePrivateIncludeComponent.new.call, "hidden div"
		end
	end

	test "a watched module's public method_added stays public" do
		with_component_files(
			"public_callback.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecyclePublicCallback
					public_class_method :method_added
				end

				class LifecyclePublicCallbackComponent < Phlex::HTML
					include LifecyclePublicCallback

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecyclePublicCallbackComponent)

			assert LifecyclePublicCallback.singleton_class < Phlex::Compiler::MixinHooks
			assert LifecyclePublicCallback.respond_to?(:method_added)
			refute LifecyclePublicCallback.respond_to?(:method_removed)
			assert_equal LifecyclePublicCallback.method_added(:unrelated), nil
		end
	end

	module FreezeWhileWatching
		def self.arm(mod, calls)
			@mod = mod
			@calls = calls
		end

		def self.called(modules)
			return unless @mod && modules.include?(@mod) && (@calls -= 1).zero?

			@mod.singleton_class.freeze
			@mod = nil
		end

		def unwatched_mixins(component, modules, **)
			super.tap { FreezeWhileWatching.called(modules) }
		end
	end

	Phlex::Compiler.singleton_class.prepend(FreezeWhileWatching)

	# Runs a block on another thread once a component's modules must be
	# watched, just before compiled methods are installed.
	module AfterWatching
		def self.arm(component, &block)
			@component = component
			@block = block
		end

		def self.watched(component)
			return unless @component.equal?(component) && (block = @block)

			@block = nil
			Thread.new(&block).join
		end

		def watch_mixins(component, *, strict: true)
			super.tap { AfterWatching.watched(component) if strict }
		end
	end

	Phlex::Compiler.singleton_class.prepend(AfterWatching)

	test "an empty module included into a subclass on another thread just before installing is watched" do
		with_component_files(
			"last_moment.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleLastMomentHelpers
				end

				class LifecycleLastMomentParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleLastMomentChild < LifecycleLastMomentParent
				end
			RUBY
		) do |(path)|
			AfterWatching.arm(LifecycleLastMomentChild) { LifecycleLastMomentChild.include(LifecycleLastMomentHelpers) }
			Phlex::Compiler.compile_file(path, components: [LifecycleLastMomentParent])
			assert LifecycleLastMomentChild.include?(LifecycleLastMomentHelpers)

			LifecycleLastMomentHelpers.define_method(:div) { |**| plain("helper div") }
			assert_equal LifecycleLastMomentChild.new.call, "helper div"
			assert_equal LifecycleLastMomentParent.new.call, "<div>x</div>"
		end
	end

	test "an empty module a method_added callback mixes into a watched module while compiling is watched" do
		with_component_files(
			"callback_mixin.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleCallbackMixinEmpty
				end

				module LifecycleCallbackMixinHelpers
				end

				class LifecycleCallbackMixin < Phlex::HTML
					include LifecycleCallbackMixinHelpers

					def self.method_added(name)
						super
						LifecycleCallbackMixinHelpers.include(LifecycleCallbackMixinEmpty) if name == :view_template && @armed
					end

					def self.arm
						@armed = true
					end

					def view_template = div { "x" }
				end
			RUBY
		) do |(path)|
			LifecycleCallbackMixin.arm
			Phlex::Compiler.compile_file(path, components: [LifecycleCallbackMixin])
			assert LifecycleCallbackMixin.include?(LifecycleCallbackMixinEmpty)

			LifecycleCallbackMixinEmpty.define_method(:div) { |**| plain("empty div") }
			assert_equal LifecycleCallbackMixin.new.call, "empty div"
		end
	end

	test "a watched module nothing inlines from any more mixes in a module with a frozen singleton class" do
		with_component_files(
			"abandoned.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleAbandonedHelpers
				end

				class LifecycleAbandoned < Phlex::HTML
					include LifecycleAbandonedHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do
			assert_raises(RuntimeError) do
				Sabotage.active = true
				Phlex::Compiler.compile(LifecycleAbandoned)
			ensure
				Sabotage.active = false
			end
			assert LifecycleAbandonedHelpers.singleton_class < Phlex::Compiler::MixinHooks

			frozen = Module.new
			frozen.singleton_class.freeze
			LifecycleAbandonedHelpers.include(frozen)
			assert LifecycleAbandonedHelpers.include?(frozen)
		end
	end

	test "a module whose singleton class overrides prepend is still watched" do
		with_component_files(
			"prepend_ignored.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecyclePrependIgnored
				end
				LifecyclePrependIgnored.singleton_class.define_singleton_method(:prepend) { |*| self }

				class LifecyclePrependIgnoredComponent < Phlex::HTML
					include LifecyclePrependIgnored

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecyclePrependIgnoredComponent)

			LifecyclePrependIgnored.define_method(:div) { |**| plain("module div") }
			assert_equal LifecyclePrependIgnoredComponent.new.call, "module div"
		end
	end

	test "a module frozen on another thread while it's mixed in decompiles what it could change" do
		with_component_files(
			"frozen_meanwhile.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleFrozenMeanwhileHelpers
				end

				class LifecycleFrozenMeanwhile < Phlex::HTML
					include LifecycleFrozenMeanwhileHelpers

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleFrozenMeanwhile)
			assert compiled_method?(LifecycleFrozenMeanwhile, :view_template)

			frozen = Module.new
			# Frozen between the check before watching and installing the hooks.
			FreezeWhileWatching.arm(frozen, 2)
			assert_raises(Phlex::Compiler::Error) { LifecycleFrozenMeanwhileHelpers.include(frozen) }
			refute Phlex::Compiler.inlines?(LifecycleFrozenMeanwhile)

			frozen.define_method(:div) { |**| plain("frozen div") }
			assert_equal LifecycleFrozenMeanwhile.new.call, "frozen div"
		end
	end

	test "a subclass overriding <= still sees an included module hide an inlined element" do
		with_component_files(
			"comparing.rb" => <<~RUBY
				# frozen_string_literal: true
				class LifecycleComparingParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleComparingChild < LifecycleComparingParent
					def self.<=(other) = false
				end

				module LifecycleHidesFromComparing
					def div = nil
					undef_method :div
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleComparingChild)
			assert_equal LifecycleComparingChild.new.call, "<div>x</div>"

			LifecycleComparingChild.include(LifecycleHidesFromComparing)
			assert_raises(NoMethodError) { LifecycleComparingChild.new.call }
		end
	end

	test "a component defining to_ary is still found when its module changes" do
		with_component_files(
			"to_ary.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleToAryHelpers
				end

				class LifecycleToAry < Phlex::HTML
					include LifecycleToAryHelpers

					def self.to_ary = []

					def view_template = div { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleToAry)

			LifecycleToAryHelpers.define_method(:div) { |**| plain("helper div") }
			assert_equal LifecycleToAry.new.call, "helper div"
		end
	end

	test "an element a method_added callback defines while compiling takes effect" do
		with_component_files(
			"reentrant.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleReentrantHelpers
				end

				class LifecycleReentrant < Phlex::HTML
					include LifecycleReentrantHelpers

					def self.arm(&block)
						@armed = block
					end

					def self.method_added(name)
						super

						if name == :view_template && (armed = @armed)
							@armed = nil
							armed.call
						end
					end

					def view_template
						div { "x" }
						span { "y" }
					end
				end
			RUBY
		) do
			LifecycleReentrant.arm { LifecycleReentrantHelpers.define_method(:div) { |**| plain("module div") } }
			Phlex::Compiler.compile(LifecycleReentrant)
			assert_equal LifecycleReentrant.new.call, "module div<span>y</span>"

			LifecycleReentrant.arm { LifecycleReentrant.define_method(:span) { |**| plain("class span") } }
			Phlex::Compiler.recompile(LifecycleReentrant)
			assert_equal LifecycleReentrant.new.call, "module divclass span"
		end
	end

	test "a module hiding an element, included by a method_added callback while compiling, takes effect" do
		with_component_files(
			"reentrant_hidden.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleReentrantHides
					def div = nil
					undef_method :div
				end

				class LifecycleReentrantHidden < Phlex::HTML
					def self.method_added(name)
						super
						include(LifecycleReentrantHides) if name == :view_template && @armed
					end

					def self.arm
						@armed = true
					end

					def view_template = div { "x" }
				end
			RUBY
		) do
			LifecycleReentrantHidden.arm
			Phlex::Compiler.compile(LifecycleReentrantHidden)
			assert_raises(NoMethodError) { LifecycleReentrantHidden.new.call }
		end
	end

	test "a method_added callback that changes an element every time it's compiled is refused" do
		with_component_files(
			"unsettled.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleUnsettledHelpers
				end

				class LifecycleUnsettled < Phlex::HTML
					include LifecycleUnsettledHelpers

					def self.method_added(name)
						super

						if name == :view_template && @armed
							LifecycleUnsettledHelpers.define_method(:div) { |**| plain("div") }
							LifecycleUnsettledHelpers.remove_method(:div)
						end
					end

					def self.arm
						@armed = true
					end

					def view_template = div { "x" }
				end
			RUBY
		) do |(path)|
			LifecycleUnsettled.arm
			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(LifecycleUnsettled) }
			assert_equal error.message, "LifecycleUnsettledHelpers kept changing what was inlined each time it was compiled again."
			assert generations_of(path) <= 11
		end
	end

	test "a method_added callback that changes an element every time it's compiled lazily is reported and still renders" do
		with_component_files(
			"unsettled_lazy.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleUnsettledLazyHelpers
				end

				class LifecycleUnsettledLazy < Phlex::HTML
					include LifecycleUnsettledLazyHelpers

					def self.method_added(name)
						super

						if name == :view_template && @armed
							LifecycleUnsettledLazyHelpers.define_method(:div) { |**| plain("div") }
							LifecycleUnsettledLazyHelpers.remove_method(:div)
						end
					end

					def self.arm
						@armed = true
					end

					def view_template = div { "x" }
				end
			RUBY
		) do
			LifecycleUnsettledLazy.arm
			failures = []
			Phlex::Compiler.enable!(on_failure: -> (component, error) { failures << [component, error.class] if component == LifecycleUnsettledLazy })
			begin
				assert_equal LifecycleUnsettledLazy.new.call, "<div>x</div>"
			ensure
				Phlex::Compiler.disable!
			end
			assert_equal failures, [[LifecycleUnsettledLazy, Phlex::Compiler::Error]]
		end
	end

	test "modules overriding singleton_class? and including classes overriding ancestors are still watched" do
		with_component_files(
			"singleton_claims.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleClaimsSingleton
					def self.singleton_class? = true
				end

				module LifecycleOverriddenAncestry
				end

				class LifecycleClaimsSingletonParent < Phlex::HTML
					def view_template
						div { "x" }
						span { "y" }
					end
				end

				class LifecycleClaimsSingletonChild < LifecycleClaimsSingletonParent
					include LifecycleClaimsSingleton
				end

				class LifecycleOverriddenAncestryChild < LifecycleClaimsSingletonParent
					include LifecycleOverriddenAncestry

					def self.ancestors = [self]
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleClaimsSingletonParent)
			assert_equal LifecycleClaimsSingletonParent.instance_variable_get(:@__phlex_inlined__), Set[:div, :span]

			LifecycleClaimsSingleton.define_method(:div) { |**| plain("claimed div") }
			assert_equal LifecycleClaimsSingletonChild.new.call, "claimed div<span>y</span>"

			LifecycleOverriddenAncestry.define_method(:span) { |**| plain("overridden span") }
			assert_equal LifecycleOverriddenAncestryChild.new.call, "<div>x</div>overridden span"
			assert_equal LifecycleClaimsSingletonParent.new.call, "<div>x</div><span>y</span>"
		end
	end

	test "a subclass's module changed on another thread while its parent compiles takes effect" do
		with_component_files(
			"concurrent_subclass.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleConcurrentSubclassHelpers
				end

				class LifecycleConcurrentParent < Phlex::HTML
					def view_template = div { "x" }
				end

				class LifecycleConcurrentChild < LifecycleConcurrentParent
					include LifecycleConcurrentSubclassHelpers
				end
			RUBY
		) do
			Interleave.pending = -> { LifecycleConcurrentSubclassHelpers.define_method(:div) { |**| plain("concurrent div") } }
			Phlex::Compiler.compile(LifecycleConcurrentParent)

			assert_equal LifecycleConcurrentChild.new.call, "concurrent div"
			assert_equal LifecycleConcurrentParent.new.call, "<div>x</div>"
		ensure
			Interleave.pending = nil
		end
	end

	test "modules overriding singleton_class, and subclasses overriding ancestors, are still watched" do
		with_component_files(
			"singleton_override.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSingletonDecoy
				end

				module LifecycleOverridesSingleton
					def self.singleton_class = LifecycleSingletonDecoy
				end

				class LifecycleOverridesSingletonComponent < Phlex::HTML
					include LifecycleOverridesSingleton

					def view_template
						div { "x" }
						span { "y" }
					end
				end

				class LifecycleHidesParent < LifecycleOverridesSingletonComponent
					def self.ancestors = [self]
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleOverridesSingletonComponent)

			LifecycleOverridesSingleton.define_method(:div) { |**| plain("real div") }
			assert_equal LifecycleOverridesSingletonComponent.new.call, "real div<span>y</span>"

			later = Module.new
			LifecycleHidesParent.include(later)
			later.define_method(:span) { |**| plain("later span") }
			assert_equal LifecycleHidesParent.new.call, "real divlater span"
		end
	end

	test "a module with a frozen singleton class is fine when nothing is inlined" do
		with_component_files(
			"frozen_uninlined.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleFrozenUninlined
					def greeting = "hi"
				end
				LifecycleFrozenUninlined.singleton_class.freeze

				class LifecycleFrozenUninlinedComponent < Phlex::HTML
					include LifecycleFrozenUninlined

					def view_template = plain(greeting)
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleFrozenUninlinedComponent)

			refute Phlex::Compiler.inlines?(LifecycleFrozenUninlinedComponent)
			assert_equal LifecycleFrozenUninlinedComponent.new.call, "hi"
		end
	end

	test "a module mixed into Phlex::SGML is watched" do
		with_component_files(
			"sgml_mixin.rb" => <<~RUBY
				# frozen_string_literal: true
				module LifecycleSGMLElements
					extend Phlex::SGML::Elements

					register_element :lifecycle_everywhere
				end

				# As if mixed in before anything was compiled, so Phlex::SGML's hook doesn't see it.
				Module.instance_method(:include).bind_call(Phlex::SGML, LifecycleSGMLElements)

				class LifecycleUsesSGMLMixin < Phlex::HTML
					def view_template = lifecycle_everywhere { "x" }
				end
			RUBY
		) do
			Phlex::Compiler.compile(LifecycleUsesSGMLMixin)
			assert_equal LifecycleUsesSGMLMixin.new.call, "<lifecycle-everywhere>x</lifecycle-everywhere>"

			LifecycleSGMLElements.define_method(:lifecycle_everywhere) { |**| plain("redefined everywhere") }
			assert_equal LifecycleUsesSGMLMixin.new.call, "redefined everywhere"
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
