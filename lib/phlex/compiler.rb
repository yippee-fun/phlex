# frozen_string_literal: true

require "prism"
require "refract"

# Rewrites component methods ahead of time so that element calls become direct
# buffer appends. Compilation is opt-in and safe to skip: an uncompiled
# component renders exactly the same, just slower.
#
# Use `Phlex::Compiler.compile(component)` to compile a class, or
# `Phlex::Compiler.enable!` to compile each class on its first render.
# `Phlex::Compiler.explain(component)` lists what's left to the runtime and why.
#
# A component's live methods say which files and lines define them. Each file
# is parsed with Prism and converted to a Refract tree, and FileCompiler
# compiles the definitions at those lines, after reopening the class and
# module statements around them with a probe so Ruby confirms which class they
# name. MethodCompiler decides what each call means, using an Environment built
# once per class body, and leaves Output nodes in the tree where text is
# appended. The Emitter then lowers those to guarded buffer appends. The
# compiled definitions are evaluated inside the original nesting under a path
# of their own, and exceptions are mapped back to the real file.
#
# The compiler is meant to be invisible: a compiled component renders exactly
# what it would have uncompiled, and code that can't be compiled faithfully is
# refused with a Phlex::Compiler::Error naming the file and line rather than
# compiled approximately. Refused: a method marked `ruby2_keywords`, a `using`
# that applies to only part of its file, two definitions of a method on one
# line, a local named like one the compiler generates (`__phlex_â¦`), a file
# edited since it was loaded, and redefining an inlined element or helper on
# a single instance with `extend` or a singleton method. Redefining one on a
# class, by including a module, or on a module already included recompiles
# whatever inlined it.
#
# Three differences remain, all deliberate:
# - Attributes with literal keys are serialised without the attribute cache, so
#   a value's `to_s`, `to_h` or `iso8601` runs on every render rather than once
#   per distinct set of attributes.
# - Method#source_location of a compiled method names the generated source;
#   exceptions are mapped back to the real file.
# - A module mixed into a compiled component keeps `include`, `prepend`,
#   `method_added`, `method_removed` and `method_undefined` as public,
#   protected or private as they were when the component was compiled.
#
# Methods a component gains from mixins aren't compiled, which only costs speed.
module Phlex::Compiler
	# Compiled code is evaluated under a path of its own so its line numbers
	# never collide with the file's, and each compilation of a file gets a new
	# one so exceptions from an old generation still map correctly.
	Generation = Data.define(:path, :lines)

	# A live method and the line in the file being compiled that defines it.
	Target = Data.define(:component, :name, :line, :compiled, :replaced)

	# What reopening a definition's class and module statements reached.
	Probe = Data.define(:component, :set, :method_resolver)

	MODULE_ANCESTORS = Module.instance_method(:ancestors)
	MODULE_SINGLETON_CLASS = Module.instance_method(:singleton_class?)
	MODULE_LE = Module.instance_method(:<=)
	MODULE_LT = Module.instance_method(:<)
	KERNEL_SINGLETON_CLASS = Kernel.instance_method(:singleton_class)
	KERNEL_FROZEN = Kernel.instance_method(:frozen?)
	MODULE_INSTANCE_METHODS = Module.instance_method(:instance_methods)
	MODULE_PRIVATE_INSTANCE_METHODS = Module.instance_method(:private_instance_methods)
	MODULE_PREPEND = Module.instance_method(:prepend)
	MODULE_PRIVATE_METHOD_DEFINED = Module.instance_method(:private_method_defined?)
	MODULE_PROTECTED_METHOD_DEFINED = Module.instance_method(:protected_method_defined?)

	MUTEX = Mutex.new

	# component => the exception that stopped it compiling on first render
	FAILURES = {}.compare_by_identity

	DEFAULT_FAILURE_HANDLER = lambda do |component, error|
		warn "Phlex::Compiler couldn't compile #{component}, so it renders uncompiled: #{error.class}: #{error.message}\n\t#{error.backtrace&.first(5)&.join("\n\t")}"
	end

	PROBE_PATH = "(phlex compiler probe)"

	# Entered in the source maps as the first compilation starts, so Phlex::SGML's hooks,
	# which do nothing while it's empty, report changes made meanwhile. No
	# method is ever defined at this path.
	STARTED_PATH = "(phlex compiler started)"
	SCOPE_PATH = File.expand_path("compiler/scope.rb", __dir__)

	# Bindings handed over by compiler/scope.rb as it's loaded.
	SCOPES = []

	@enabled = false
	@generations = 0
	# [target, names] changes reported while another thread was compiling
	@reported = []
	# [target, names] changes made on the compiling thread itself, say by a
	# method_added callback, handled once its compilation is done
	@deferred = []
	# component => names the compiler is defining, each expected to be reported once
	@installing = {}.compare_by_identity
	@on_failure = DEFAULT_FAILURE_HANDLER

	def self.enabled? = @enabled

	# Compile each component on its first render. A component that fails to
	# compile is reported to `on_failure` once and keeps rendering uncompiled,
	# so a compiler bug costs speed, never a page.
	#
	# Only the main Ractor compiles. Other Ractors render a component as they
	# find it, without waiting for a compilation in progress, so compile with
	# `Phlex::Compiler.compile` before starting them.
	def self.enable!(on_failure: DEFAULT_FAILURE_HANDLER)
		Phlex::SGML.prepend(LazyCompilation) unless Phlex::SGML < LazyCompilation
		@on_failure = on_failure
		@enabled = true
	end

	def self.disable!
		@enabled = false
	end

	def self.inlines?(component)
		(inlined = component.instance_variable_get(:@__phlex_inlined__)) && !inlined.empty?
	end

	def self.compiled?(component)
		component.instance_variable_get(:@__phlex_compiled__) == true
	end

	# The failure check and the compilation share the lock, so two first
	# renders racing each other still compile and report once, and a render
	# that starts while a recompilation holds it waits for the new methods.
	# The handler runs outside it, since it may well render something.
	def self.compile_on_first_render(component)
		return unless Phlex.__main_ractor__?

		error = synchronize do
			return if compiled?(component) || FAILURES.key?(component)

			begin
				compile_ancestry(component)
				invalidate_deferred
				nil
			rescue StandardError, ScriptError => e
				FAILURES[component] = e
			end
		end

		@on_failure.call(component, error) if error
	end

	# Compiles the methods of the component and its Phlex ancestors wherever
	# they're defined. The files must already be loaded.
	def self.compile(component)
		component!(component)

		synchronize { compile_ancestry(component) }
	end

	# Holds the lock, then handles the changes made meanwhile on this thread.
	# A failed compilation drops them rather than hiding its own exception.
	def self.synchronize
		return yield if MUTEX.owned?

		MUTEX.synchronize do
			yield.tap { invalidate_deferred }
		ensure
			@deferred.clear
		end
	end

	def self.invalidate_deferred
		rounds = 0

		until @deferred.empty?
			if (rounds += 1) > 10
				raise Error, "#{@deferred.map(&:first).uniq.join(', ')} kept changing what was inlined each time it was compiled again."
			end

			deferred = @deferred
			@deferred = []
			affected = deferred.flat_map { |target, names| affected_by(target, names | hidden_names(target)) }
			uniq_by_identity(affected).each { |component| recompile(component) }
		end
	rescue Exception
		@deferred.clear
		raise
	end

	def self.compile_ancestry(component)
		return if component.frozen? || compiled?(component)

		ancestors = phlex_ancestors(component).reject { |ancestor| ancestor.frozen? || compiled?(ancestor) }
		components = ancestors.select { |ancestor| live?(ancestor) }

		components.flat_map { |ancestor| defining_files(ancestor) }.uniq.each do |path|
			compile_file(path, components:)
		end

		ancestors.each { |ancestor| ancestor.instance_variable_set(:@__phlex_compiled__, true) }
	end

	# Why parts of the files defining the component and its Phlex ancestors are
	# left to the runtime, as Diagnostics::Diagnostic records in file order.
	# Nothing is compiled; an already compiled method is reported as such.
	def self.explain(component)
		component!(component)

		ancestors = phlex_ancestors(component)

		failures = ancestors.filter_map do |ancestor|
			next unless (error = FAILURES[ancestor])

			Diagnostics::Diagnostic.new(path: constant_source_path(ancestor), line: nil, message: "compiling #{ancestor} raised #{error.class}: #{error.message}")
		end

		failures + ancestors.flat_map { |ancestor| defining_files(ancestor) }.uniq.flat_map do |path|
			diagnostics = Diagnostics.new(path, strict: false)
			FileCompiler.new(path, targets: targets(path, ancestors), diagnostics:).compile(parse(File.read(path), path))
			diagnostics.to_a
		end
	end

	# Compiles the methods that the given components, by default every loaded
	# one, define in an already-loaded file.
	def self.compile_file(path, components: loaded_components, recompile: false, inline: true)
		unless MUTEX.owned?
			return synchronize { compile_file(path, components:, recompile:, inline:) }
		end

		unless File.exist?(path)
			raise ArgumentError, "Canât compile #{path} because it doesnât exist."
		end

		Phlex.__add_compiled_source_map__(STARTED_PATH, Generation.new(path: STARTED_PATH, lines: {}.freeze)) unless Phlex.__compiled_source_maps__.key?(STARTED_PATH)

		parse_result = Prism.parse(without_byte_order_mark(File.read(path)), filepath: path)
		targets = targets(path, components, recompile:)

		# Watched before calls are resolved, so a module changed meanwhile is
		# reported. A change between here and recording what was inlined is
		# compiled again below.
		reported = @reported.size
		components = uniq_by_identity(targets.each_value.map(&:component))

		# Subclasses inherit what's inlined, so their modules are watched too. A
		# module that can't be watched only matters if something is inlined.
		if inline
			uniq_by_identity(components.flat_map { |component| [component, *descendants_of(component)] }).each do |component|
				watch_mixins(component, strict: false)
			end
		end

		file_compiler = FileCompiler.new(path, targets:, recompile:, inline:)
		results = file_compiler.compile(Refract::Converter.new.visit(parse_result.value)).reject { |result| result.compiled_snippets.empty? }
		return if results.empty?

		# Before anything is replaced, modules mixed in meanwhile are watched,
		# and those of anything running inlined code must be.
		if inline
			components.each { |component| watch_mixins(component, strict: false) }
			watch_inlining_mixins(results)
		end

		program = Refract::StatementsNode.new(
			body: [*file_compiler.usings, *results.map { |result| wrap_in_namespace(result.namespace, result.compiled_snippets) }]
		)
		formatting_result = Refract::Formatter.new(starting_line: 2).format_node(program)

		compiled_path = -"#{path} (compiled #{@generations += 1})"

		lines = {}
		formatting_result.source_map.each_with_index do |original_line, generated_line|
			lines[generated_line] = original_line if original_line
		end

		# Added before the methods exist, so nothing running them finds a line unmapped.
		Phlex.__add_compiled_source_map__(compiled_path, Generation.new(path: -path, lines: lines.freeze))

		installing(results) do
			without_redefinition_warnings do
				eval(
					"#{magic_comments(parse_result)}#{formatting_result.source}",
					scope,
					compiled_path,
					1
				)
			end
		end

		installing(results) do
			results.each do |result|
				result.visibilities.each do |name, visibility|
					result.component.__send__(visibility, name) unless visibility == :public
				end
			end
		end

		results.each do |result|
			inlined = result.component.instance_variable_get(:@__phlex_inlined__) || Set.new
			result.component.instance_variable_set(:@__phlex_inlined__, (inlined | result.inlined).freeze)
		end

		# A change reported from another thread before what was inlined was
		# recorded above may not have been seen, so what it affects is compiled
		# again. One reported from here on finds the record itself.
		missed = @reported.drop(reported)
		@reported.clear

		if inline
			# A module mixed in since the last watch, here or on another thread,
			# saw nothing inlined yet, so it wasn’t watched. What it defined
			# before its hooks were installed wasn’t reported either.
			begin
				if missed.any? || @deferred.any?
					missed += watch_inlining_mixins(results).map { |mod| [mod, method_names(mod)] }
				end
			rescue Error
				uniq_by_identity(results.map(&:component)).each { |component| decompile(component) }
				raise
			end

			uniq_by_identity(results.map(&:component)).each do |component|
				recompile_unlocked(component) if missed.any? { |target, names| inlines_any?(component, names | hidden_names(target)) && related(target).include?(component) }
			end
		end

		nil
	end

	# The modules of anything running inlined code must be watched.
	def self.watch_inlining_mixins(results)
		inlining = uniq_by_identity(results.reject { |result| result.inlined.empty? }.map(&:component))
		uniq_by_identity(inlining.flat_map { |component| [component, *descendants_of(component)] }).flat_map do |component|
			watch_mixins(component)
		end
	end

	# Whether a change to the target can reach inlined code.
	def self.affects_inlined_code?(target)
		related(target).any? { |klass| inlines?(klass) }
	end

	def self.inlines_any?(component, names)
		(inlined = component.instance_variable_get(:@__phlex_inlined__)) && names.any? { |name| inlined.include?(name) }
	end

	def self.installing(results)
		installing = @installing
		@installing = {}.compare_by_identity

		results.each do |result|
			(@installing[result.component] ||= Set.new).merge(result.visibilities.keys)
		end

		yield
	ensure
		@installing = installing
	end

	# Whether this is the compiler's own definition being reported, rather than
	# one made by a callback while it's installed.
	def self.installed_by_compiler?(target, names)
		case names
		in [name] then !!@installing[target]&.delete?(name)
		else false
		end
	end

	# Called by Phlex::SGML and MixinHooks when methods are defined on, removed
	# from or mixed into a class, singleton class or module. A compiled class
	# above or below it, or including it, that inlined one of them is
	# recompiled, and with the change now loaded it
	# stops inlining that name, so the change takes effect just as it would
	# have uncompiled. An override on a single instance can't be compiled for,
	# so it's refused. A change made on the compiling thread itself is handled
	# once that compilation is done.
	def self.inlining_changed(target, names)
		return changed_on_another_ractor(target, names) unless Phlex.__main_ractor__?

		if MUTEX.owned?
			@deferred << [target, names] unless installed_by_compiler?(target, names)
			return
		end

		# A compilation on another thread may have resolved these names without
		# having recorded what it inlined yet, so it checks them when it has.
		@reported << [target, names] if MUTEX.locked?

		affected_by(target, names).each { |component| recompile(component) }
	end

	# Only the main Ractor can compile again, and the methods bound above
	# can't be shared before Ruby 4.0, so another Ractor checks an override
	# on a single instance with plain calls and refuses anything else.
	def self.changed_on_another_ractor(target, names)
		unless target.singleton_class?
			raise Error, "#{names.join(', ')} can't be redefined on #{target} outside the main Ractor once something is compiled."
		end

		affected = target.ancestors.select { |klass| inlines_any?(klass, names) }
		raise single_instance_error(names, affected) unless affected.empty?
	end

	def self.single_instance_error(names, affected)
		Error.new("#{names.join(', ')} can't be redefined on a single instance: #{affected.join(', ')} compiled it inline. Redefine it on the class, before compiling.")
	end

	# The compiled classes to recompile for a change, refusing one that can't be.
	def self.affected_by(target, names)
		affected = related(target).select { |klass| inlines_any?(klass, names) }
		return affected if affected.empty?

		raise single_instance_error(names, affected) if MODULE_SINGLETON_CLASS.bind_call(target)

		if (frozen = affected.select(&:frozen?)).any?
			raise Error, "#{names.join(', ')} can't be redefined: #{frozen.join(', ')} compiled it inline and was frozen without Phlex::SGML.freeze restoring it."
		end

		affected
	end

	# The classes whose compiled methods a change to the target can affect.
	def self.related(target)
		if MODULE_SINGLETON_CLASS.bind_call(target)
			MODULE_ANCESTORS.bind_call(target)
		elsif Class === target
			MODULE_ANCESTORS.bind_call(target) + descendants_of(target)
		else
			uniq_by_identity(descendants_of(Phlex::SGML).map { |klass| MODULE_ANCESTORS.bind_call(klass) }.select { |ancestors| ancestors.include?(target) }.flatten(1))
		end
	end

	# A compiled component inlines elements and helpers its modules define, so
	# those modules, and any mixed in later, report their changes too. That
	# includes modules mixed into Phlex::SGML, but not Object's.
	def self.watch_mixins(component, modules = MODULE_ANCESTORS.bind_call(component).take_while { |ancestor| ancestor != Object }, strict: true)
		unwatched_mixins(component, modules, strict:).filter_map do |mod|
			MODULE_PREPEND.bind_call(KERNEL_SINGLETON_CLASS.bind_call(mod), mixin_hooks_for(mod))
			mod
		rescue FrozenError
			# Frozen by another thread since it was checked.
			raise if unwatched_mixins(component, [mod], strict:).any?
		end
	end

	def self.uniq_by_identity(objects)
		objects.each_with_object({}.compare_by_identity) { |object, seen| seen[object] = true }.keys
	end

	# MixinHooks, or a copy keeping each hook as public, protected or private
	# as the module has it.
	def self.mixin_hooks_for(mod)
		singleton = KERNEL_SINGLETON_CLASS.bind_call(mod)
		names = MixinHooks.instance_methods(false) + MixinHooks.private_instance_methods(false)
		changed = names.filter_map do |name|
			visibility = method_visibility(singleton, name)
			[name, visibility] unless visibility == method_visibility(MixinHooks, name)
		end
		return MixinHooks if changed.empty?

		Module.new do
			include MixinHooks

			changed.each { |name, visibility| __send__(visibility, name) }
		end
	end

	def self.method_visibility(mod, name)
		if MODULE_PRIVATE_METHOD_DEFINED.bind_call(mod, name)
			:private
		elsif MODULE_PROTECTED_METHOD_DEFINED.bind_call(mod, name)
			:protected
		else
			:public
		end
	end

	# The modules still to be watched. A module whose singleton class is frozen
	# can't be, so it's refused, or when not `strict`, skipped.
	def self.unwatched_mixins(component, modules, strict: true)
		unwatched = modules.reject do |mod|
			Class === mod || KERNEL_FROZEN.bind_call(mod) || MODULE_LT.bind_call(KERNEL_SINGLETON_CLASS.bind_call(mod), MixinHooks)
		end

		unwatched.reject do |mod|
			next false unless KERNEL_FROZEN.bind_call(KERNEL_SINGLETON_CLASS.bind_call(mod))
			next true unless strict

			raise Error, "#{mod} can't be watched for changes because its singleton class is frozen, so #{component} can't inline what it defines."
		end
	end

	# Mixes modules into a class or module, refusing any that couldn't be
	# watched before anything changes. Whatever `include` or `prepend` actually
	# added is then watched, and what inlined one of its methods recompiled. A
	# module added in place of those given that can't be watched is already
	# mixed in, so what it could affect is decompiled before it's refused.
	# Whatever was added is handled even when `include` or `prepend` raises,
	# say from an `included` callback.
	def self.mix_in(target, modules, watch: true)
		unwatched_mixins(target, modules.grep(Module).flat_map { |mod| MODULE_ANCESTORS.bind_call(mod) }) if watch

		before = MODULE_ANCESTORS.bind_call(target)
		begin
			yield
		ensure
			mixed_in(target, added_ancestors(before, MODULE_ANCESTORS.bind_call(target)), watch:)
		end
	end

	def self.mixed_in(target, added, watch:)
		if watch
			begin
				watch_mixins(target, added)
			rescue Error
				related(target).select { |klass| inlines?(klass) }.each { |klass| decompile(klass) }
				raise
			end
		end

		inlining_changed(target, added.flat_map { |mod| method_names(mod) } | hidden_names(target))
	end

	# A module can also hide a method with `undef_method`, which no listing of
	# its methods shows. These are the inlined names that no longer resolve in
	# a class that has the target in its ancestry and runs the inlined code.
	def self.hidden_names(target)
		related = related(target)
		below = related.select { |klass| Class === klass && MODULE_ANCESTORS.bind_call(klass).include?(target) }

		related.flat_map do |klass|
			next [] unless (inlined = klass.instance_variable_get(:@__phlex_inlined__))

			inheritors = below.select { |other| MODULE_LE.bind_call(other, klass) }
			inlined.reject { |name| inheritors.all? { |inheritor| resolves?(inheritor, name) } }
		end
	end

	def self.resolves?(klass, name)
		Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(klass, name)
		true
	rescue NameError
		false
	end

	# The ancestors in `after` that aren't in `before`, counting each
	# occurrence, since `prepend` can add a module already further up.
	def self.added_ancestors(before, after)
		remaining = before.tally
		after.reject { |mod| remaining[mod].to_i > 0 && (remaining[mod] -= 1) }
	end

	# The names a module defines, read without dispatching to the module.
	def self.method_names(mod)
		MODULE_INSTANCE_METHODS.bind_call(mod) + MODULE_PRIVATE_INSTANCE_METHODS.bind_call(mod)
	end

	# Compiles the component's methods again, replacing the compiled ones.
	def self.recompile(component, inline: true)
		synchronize { recompile_unlocked(component, inline:) }
	end

	# When a file can't be compiled again, its old compiled methods stay in
	# place, so what they inlined stays on record and later changes are still
	# reported.
	def self.recompile_unlocked(component, inline: true)
		inlined = component.remove_instance_variable(:@__phlex_inlined__) if component.instance_variable_defined?(:@__phlex_inlined__)

		defining_files(component).each do |path|
			compile_file(path, components: [component], recompile: true, inline:)
		end
	rescue Exception
		if inlined
			recorded = component.instance_variable_get(:@__phlex_inlined__) || Set.new
			component.instance_variable_set(:@__phlex_inlined__, (recorded | inlined).freeze)
		end

		raise
	end

	# Reinstalls the component's original definitions. A frozen class can't be
	# recompiled when something it inlined changes, so Phlex::SGML.freeze
	# restores a compiled class first.
	def self.decompile(component)
		recompile(component, inline: false)
	end

	# Reopens the class and module statements around a definition with nothing
	# inside but a call reporting the class reached and what `Set` names there.
	# The method resolver captures the file's refinements, so element and helper
	# lookup uses the same lexical scope as the compiled definitions. The
	# statements are copied without their superclasses, so they only reopen.
	# Bind and call separately: TruffleRuby's bind_call loses the caller's refinements.
	def self.probe(namespace, usings: [])
		report = parse(<<~RUBY, PROBE_PATH).statements.body.first
			::Phlex::Compiler.__probe__(self, defined?(Set) && Set, ->(component, name) {
				::Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind(component).call(name)
			})
		RUBY
		program = Refract::StatementsNode.new(body: [*usings, wrap_in_namespace(namespace, [report])])
		source = Refract::Formatter.new.format_node(program).source

		Thread.current[:__phlex_compiler_probe__] = nil
		eval(source, scope, PROBE_PATH, 1)
		Thread.current[:__phlex_compiler_probe__] or raise Error, "Reopening the class and module statements didn't reach a class body:\n#{source}"
	end

	# A fresh top-level binding, so refinements a compiled file activates stay
	# in it, as they would in a real file. TOPLEVEL_BINDING is shared, and a
	# `using` evaluated there applies to everything evaluated there after.
	def self.scope
		load SCOPE_PATH
		SCOPES.pop
	end

	def self.__probe__(component, set, method_resolver)
		Thread.current[:__phlex_compiler_probe__] = Probe.new(component:, set:, method_resolver:)
	end

	# Whether the class is still the one its name refers to. After a reload the
	# old class object lingers, and reopening its name would reach the new one.
	def self.live?(component)
		(name = component.name) && Object.const_get(name).equal?(component)
	rescue NameError
		false
	end

	def self.phlex_ancestors(component)
		component.ancestors.take_while { |ancestor| ancestor != Phlex::SGML }.select { |ancestor| Class === ancestor }
	end

	def self.loaded_components
		descendants_of(Phlex::SGML).select { |component| live?(component) }
	end

	# Class#subclasses is called directly, so a class overriding it can't hide
	# or invent descendants.
	SUBCLASSES = Class.instance_method(:subclasses)

	def self.descendants_of(component)
		SUBCLASSES.bind_call(component).flat_map { |subclass| [subclass, *descendants_of(subclass)] }
	end

	# The lines in the file that define the components' live methods. A method
	# that's already compiled is traced back through its generation's map, and
	# is a target again only when recompiling. An alias has the source location
	# of the method it copied, and a method made by `attr_reader` or
	# `define_method` has none of a `def`'s source to compile, so neither is a
	# target.
	def self.targets(path, components, recompile: false)
		components.each_with_object({}) do |component, targets|
			next if component.frozen? || !live?(component)

			own_methods(component).each do |name|
				method = component.instance_method(name)
				next unless method.original_name == name && (location = method.source_location)

				source_path, line = location

				if (generation = Phlex.__compiled_source_maps__[source_path])
					next unless generation.path == path && (line = generation.lines[line])

					targets[line] = Target.new(component:, name:, line:, compiled: !recompile, replaced: true)
				elsif source_path == path && defined_by_def?(method)
					targets[line] = Target.new(component:, name:, line:, compiled: false, replaced: false)
				end
			end
		end
	end

	# Whether the method was made by `def`. Only CRuby can tell: a method from
	# `attr_reader` has no instruction sequence, and one from `define_method`
	# has a block's. Anything else, or any method elsewhere, is assumed to be,
	# so a change in how Ruby labels them makes a `def` that an `attr_reader`
	# or `define_method` replaced refused, rather than stopping compilation.
	def self.defined_by_def?(method)
		return true unless defined?(RubyVM::InstructionSequence)

		iseq = RubyVM::InstructionSequence.of(method)
		!iseq.nil? && !iseq.label.start_with?("block ")
	end

	# Module's own method listings, called directly so a class overriding them
	# can't change what the compiler sees.
	METHOD_LISTS = [:instance_methods, :private_instance_methods, :protected_instance_methods].map { |list| Module.instance_method(list) }.freeze

	# The aliases, in the component or a descendant, that share a body with
	# the component's method, as [owner, name] pairs. A descendant isn't being
	# compiled, so it's reflected on without calling its own methods, which it
	# may have overridden. A copy made by `define_method` shares the body too
	# but isn't equal to the method, so they're matched by source location.
	def self.aliases_sharing(component, name)
		method = Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(component, name)

		[component, *descendants_of(component)].flat_map do |owner|
			names = METHOD_LISTS.flat_map { |list| list.bind_call(owner, false) }

			names.filter_map do |alias_name|
				next if alias_name == name

				candidate = Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(owner, alias_name)
				[owner, alias_name] if candidate.original_name == name && candidate.source_location == method.source_location
			end
		end
	end

	# The methods the component defines itself. `initialize` runs before the
	# component has any state to render into.
	def self.own_methods(component)
		names = component.instance_methods(false) + component.private_instance_methods(false) + component.protected_instance_methods(false) - [:initialize]
		names.reject { |name| revisibilised?(component, name) }
	end

	# Changing the visibility of an inherited method lists it on the component,
	# with the component as its owner, but its source is still the ancestor's.
	def self.revisibilised?(component, name)
		location = component.instance_method(name).source_location

		component.ancestors.any? do |ancestor|
			next false if ancestor.equal?(component)

			defined = ancestor.method_defined?(name, false) || ancestor.private_method_defined?(name, false) || ancestor.protected_method_defined?(name, false)
			defined && ancestor.instance_method(name).source_location == location
		end
	end

	def self.defining_files(component)
		paths = own_methods(component).filter_map do |name|
			source_path = component.instance_method(name).source_location&.first
			Phlex.__compiled_source_maps__[source_path]&.path || source_path
		end
		paths << constant_source_path(component)
		paths.compact.uniq.select { |path| File.exist?(path) }
	end

	# The file the class was first defined in, unless its name no longer
	# resolves to it, as after a code reload.
	def self.constant_source_path(component)
		return unless live?(component)

		Object.const_source_location(component.name)&.first
	end

	def self.component!(component)
		unless Class === component && Phlex::SGML > component
			raise ArgumentError, "Expected a Phlex::SGML subclass, got #{component.inspect}."
		end
	end

	def self.parse(source, path)
		Refract::Converter.new.visit(Prism.parse(source, filepath: path).value)
	end

	# Replacing a method is the whole point, so the warning for it is noise.
	def self.without_redefinition_warnings
		verbose = $VERBOSE
		$VERBOSE = nil
		yield
	ensure
		$VERBOSE = verbose
	end

	BYTE_ORDER_MARK = "\xEF\xBB\xBF".b.freeze

	# Ruby drops a byte order mark before reading the encoding comment, but
	# Prism reads the mark as the encoding and ignores the comment.
	def self.without_byte_order_mark(source)
		source.b.start_with?(BYTE_ORDER_MARK) ? source.byteslice((BYTE_ORDER_MARK.bytesize)..) : source
	end

	# The generated source is always prefixed with exactly one line so the
	# line arithmetic stays the same whatever the file's magic comments are.
	# Emacs-style syntax lets the encoding and frozen string literal comments
	# share that line, which is the only place Ruby reads an encoding from.
	def self.magic_comments(parse_result)
		comments = ["coding: #{parse_result.encoding.name}"]
		frozen_string_literal = frozen_string_literal(parse_result)
		comments << "frozen_string_literal: #{frozen_string_literal}" unless frozen_string_literal.nil?
		"# -*- #{comments.join('; ')} -*-\n"
	end

	# Ruby only reads a frozen string literal comment from the comment block
	# before the first token, with the last valid one there winning. An
	# explicit false is forwarded too, since it isn't the same as no comment:
	# it overrides `--enable-frozen-string-literal` and unchills the strings.
	def self.frozen_string_literal(parse_result)
		first_token = first_token_offset(parse_result)

		comment = parse_result.magic_comments.reverse_each.find do |magic_comment|
			magic_comment.key_loc.start_offset < first_token &&
				magic_comment.key.tr("-", "_").casecmp?("frozen_string_literal") &&
				(magic_comment.value.casecmp?("true") || magic_comment.value.casecmp?("false"))
		end

		comment&.value&.casecmp?("true")
	end

	# The AST can't tell us where the first token is because it leaves out
	# tokens such as a lone semicolon, so the lexer's tokens are read instead.
	def self.first_token_offset(parse_result)
		Prism.lex(parse_result.source.source).value.each do |token, _state|
			next if token.type in :COMMENT | :NEWLINE | :IGNORED_NEWLINE | :EMBDOC_BEGIN | :EMBDOC_LINE | :EMBDOC_END

			return token.location.start_offset
		end

		raise Phlex::Compiler::Error, "Prism lexed #{parse_result.source.source.bytesize} bytes without an end of file token"
	end

	def self.wrap_in_namespace(namespace, body)
		namespace.reverse_each.reduce(Refract::StatementsNode.new(body:)) do |inner, scope|
			wrapped = Refract::StatementsNode.new(body: [inner])

			case scope
			in Refract::ClassNode then scope.copy(body: wrapped, superclass: nil)
			in Refract::ModuleNode then scope.copy(body: wrapped)
			end
		end
	end

	# Prepended to the singleton class of each module a compiled component
	# mixes in, to report what Phlex::SGML's own hooks would for a class.
	module MixinHooks
		def include(*modules, **kwargs)
			Phlex::Compiler.mix_in(self, modules, watch: Phlex::Compiler.affects_inlined_code?(self)) { super }
		end

		def prepend(*modules, **kwargs)
			Phlex::Compiler.mix_in(self, modules, watch: Phlex::Compiler.affects_inlined_code?(self)) { super }
		end

		private def method_added(method_name)
			Phlex::Compiler.inlining_changed(self, [method_name])
			super
		end

		private def method_removed(method_name)
			Phlex::Compiler.inlining_changed(self, [method_name])
			super
		end

		private def method_undefined(method_name)
			Phlex::Compiler.inlining_changed(self, [method_name])
			super
		end
	end

	module LazyCompilation
		def internal_call(...)
			Phlex::Compiler.compile_on_first_render(self.class) if Phlex::Compiler.enabled?

			super
		end
	end
end
