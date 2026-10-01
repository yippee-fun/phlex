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
# line, a local named like one the compiler generates (`__phlex_…`), a file
# edited since it was loaded, and redefining an inlined element or helper on
# a single instance with `extend` or a singleton method. Redefining one on a
# class or by including a module recompiles whatever inlined it.
#
# Two differences remain, both deliberate:
# - Attributes with literal keys are serialised without the attribute cache, so
#   a value's `to_s`, `to_h` or `iso8601` runs on every render rather than once
#   per distinct set of attributes.
# - Method#source_location of a compiled method names the generated source;
#   exceptions are mapped back to the real file.
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

	# compiled path => Generation
	MAP = Phlex::COMPILED_SOURCE_MAPS
	MUTEX = Mutex.new

	# component => the exception that stopped it compiling on first render
	FAILURES = {}.compare_by_identity

	DEFAULT_FAILURE_HANDLER = lambda do |component, error|
		warn "Phlex::Compiler couldn't compile #{component}, so it renders uncompiled: #{error.class}: #{error.message}\n\t#{error.backtrace&.first(5)&.join("\n\t")}"
	end

	PROBE_PATH = "(phlex compiler probe)"
	SCOPE_PATH = File.expand_path("compiler/scope.rb", __dir__)

	# Bindings handed over by compiler/scope.rb as it's loaded.
	SCOPES = []

	@enabled = false
	@generations = 0
	@on_failure = DEFAULT_FAILURE_HANDLER

	def self.enabled? = @enabled

	# Compile each component on its first render. A component that fails to
	# compile is reported to `on_failure` once and keeps rendering uncompiled,
	# so a compiler bug costs speed, never a page.
	def self.enable!(on_failure: DEFAULT_FAILURE_HANDLER)
		Phlex::SGML.prepend(LazyCompilation) unless Phlex::SGML < LazyCompilation
		@on_failure = on_failure
		@enabled = true
	end

	def self.disable!
		@enabled = false
	end

	def self.compiled?(component)
		component.instance_variable_get(:@__phlex_compiled__) == true
	end

	# The failure check and the compilation share the lock, so two first
	# renders racing each other still compile and report once. The handler
	# runs outside it, since it may well render something.
	def self.compile_on_first_render(component)
		error = MUTEX.synchronize do
			return if compiled?(component) || FAILURES.key?(component)

			begin
				compile_ancestry(component)
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

		MUTEX.synchronize { compile_ancestry(component) }
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
		unless File.exist?(path)
			raise ArgumentError, "Can’t compile #{path} because it doesn’t exist."
		end

		source = File.read(path)
		file_compiler = FileCompiler.new(path, targets: targets(path, components, recompile:), recompile:, inline:)
		results = file_compiler.compile(parse(source, path)).reject { |result| result.compiled_snippets.empty? }
		return if results.empty?

		program = Refract::StatementsNode.new(
			body: [*file_compiler.usings, *results.map { |result| wrap_in_namespace(result.namespace, result.compiled_snippets) }]
		)
		formatting_result = Refract::Formatter.new(starting_line: 2).format_node(program)

		compiled_path = "#{path} (compiled #{@generations += 1})"

		without_redefinition_warnings do
			eval(
				"#{magic_comments(source)}#{formatting_result.source}",
				scope,
				compiled_path,
				1
			)
		end

		lines = {}
		formatting_result.source_map.each_with_index do |original_line, generated_line|
			lines[generated_line] = original_line if original_line
		end
		MAP[compiled_path] = Generation.new(path:, lines: lines.freeze)

		results.each do |result|
			result.visibilities.each do |name, visibility|
				result.component.__send__(visibility, name) unless visibility == :public
			end

			inlined = result.component.instance_variable_get(:@__phlex_inlined__) || Set.new
			result.component.instance_variable_set(:@__phlex_inlined__, (inlined | result.inlined).freeze)
		end

		nil
	end

	# Called by Phlex::SGML when methods are defined on, removed from or mixed
	# into a class or singleton class. A compiled class above or below it that
	# inlined one of them is recompiled, and with the change now loaded it
	# stops inlining that name, so the change takes effect just as it would
	# have uncompiled. An override on a single instance can't be compiled for,
	# so it's refused.
	def self.inlining_changed(target, names)
		return if MUTEX.owned?

		related = target.singleton_class? ? target.ancestors : target.ancestors + descendants_of(target)
		affected = related.select do |klass|
			(inlined = klass.instance_variable_get(:@__phlex_inlined__)) && names.any? { |name| inlined.include?(name) }
		end
		return if affected.empty?

		if target.singleton_class?
			raise Error, "#{names.join(', ')} can't be redefined on a single instance: #{affected.join(', ')} compiled it inline. Redefine it on the class, before compiling."
		end

		if (frozen = affected.select(&:frozen?)).any?
			raise Error, "#{names.join(', ')} can't be redefined: #{frozen.join(', ')} compiled it inline and was frozen without Phlex::SGML.freeze restoring it."
		end

		affected.each { |component| recompile(component) }
	end

	# Compiles the component's methods again, replacing the compiled ones.
	def self.recompile(component, inline: true)
		MUTEX.synchronize do
			component.remove_instance_variable(:@__phlex_inlined__) if component.instance_variable_defined?(:@__phlex_inlined__)

			defining_files(component).each do |path|
				compile_file(path, components: [component], recompile: true, inline:)
			end
		end
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

	def self.descendants_of(component)
		component.subclasses.flat_map { |subclass| [subclass, *descendants_of(subclass)] }
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
				next unless method.original_name == name && defined_by_def?(method) && (location = method.source_location)

				source_path, line = location

				if (generation = MAP[source_path])
					next unless generation.path == path && (line = generation.lines[line])

					targets[line] = Target.new(component:, name:, line:, compiled: !recompile, replaced: true)
				elsif source_path == path
					targets[line] = Target.new(component:, name:, line:, compiled: false, replaced: false)
				end
			end
		end
	end

	# Whether the method was made by `def`. Only CRuby can tell, so elsewhere
	# every method is assumed to be, and a `def` that an `attr_reader` or
	# `define_method` replaced is refused as if the file had been edited.
	def self.defined_by_def?(method)
		return true unless defined?(RubyVM::InstructionSequence)

		RubyVM::InstructionSequence.of(method)&.label == method.original_name.name
	end

	# The aliases, in the component or a descendant, that share a body with
	# the component's method, as [owner, name] pairs. A descendant isn't being
	# compiled, so it's reflected on without calling its own methods, which it
	# may have overridden.
	def self.aliases_sharing(component, name)
		method = Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(component, name)

		[component, *descendants_of(component)].flat_map do |owner|
			names = owner.instance_methods(false) + owner.private_instance_methods(false) + owner.protected_instance_methods(false)

			names.filter_map do |alias_name|
				next if alias_name == name

				candidate = Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(owner, alias_name)
				[owner, alias_name] if candidate.original_name == name && candidate == method
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
			MAP[source_path]&.path || source_path
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

	# The generated source is always prefixed with exactly one line so the
	# line arithmetic stays the same whether or not the file freezes strings.
	def self.magic_comments(source)
		if source.lines.first(2).any? { |line| line.match?(/\A#.*frozen_string_literal:\s*true/) }
			"# frozen_string_literal: true\n"
		else
			"\n"
		end
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

	module LazyCompilation
		def internal_call(...)
			Phlex::Compiler.compile_on_first_render(self.class) if Phlex::Compiler.enabled?

			super
		end
	end
end
