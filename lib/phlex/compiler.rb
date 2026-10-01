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
# A file is parsed with Prism and converted to a Refract tree. FileCompiler
# walks the class and module nesting, resolving each constant as Ruby would,
# and hands each component's body to a ClassCompiler, which matches each
# definition to the live method before a MethodCompiler rewrites it. The
# MethodCompiler decides what each call means, using an Environment built once
# per class body, and leaves Output nodes in the tree where text is appended.
# The Emitter then lowers those to guarded buffer appends. The compiled
# definitions are evaluated inside the original nesting under a path of their
# own, and exceptions are mapped back to the real file.
#
# Known differences from uncompiled rendering, all limited to unusual code:
# - Refinements active in a compiled file don't apply to compiled methods.
# - A local variable first assigned inside an inlined element block is visible
#   for the rest of the method.
# - A `to_s` or `to_hash` with side effects on an interpolated variable or
#   splatted attributes isn't called for elements skipped by fragment selection,
#   and if it raises, text before it in the same append has already been written.
# - Attributes with literal keys are serialised without the attribute cache, so
#   a value's `to_s`, `to_h` or `iso8601` runs on every render.
# - Element methods a compiled method inlines can't be overridden by a subclass
#   loaded after compilation, by a module included afterwards, or by singleton
#   methods on an instance. Subclasses loaded before compilation are detected.
# - Methods a component gains from mixins aren't compiled.
# - `break` out of a `head` block skips the automatic flush at runtime but not
#   when compiled.
# - A method marked with `ruby2_keywords` loses that flag when compiled, since
#   Ruby offers no way to read it back.
module Phlex::Compiler
	# Compiled code is evaluated under a path of its own so its line numbers
	# never collide with the file's, and each compilation of a file gets a new
	# one so exceptions from an old generation still map correctly.
	Generation = Data.define(:path, :lines)

	# compiled path => Generation
	MAP = Phlex::COMPILED_SOURCE_MAPS
	MUTEX = Mutex.new

	@enabled = false
	@generations = 0

	def self.enabled? = @enabled

	# Compile each component on its first render.
	def self.enable!
		Phlex::SGML.prepend(LazyCompilation) unless Phlex::SGML < LazyCompilation
		@enabled = true
	end

	def self.disable!
		@enabled = false
	end

	def self.compiled?(component)
		component.instance_variable_get(:@__phlex_compiled__) == true
	end

	# Compiles every file that defines methods on the component or on its
	# Phlex ancestors. The files must already be loaded.
	def self.compile(component)
		component!(component)

		return if component.frozen?

		MUTEX.synchronize do
			return if compiled?(component)

			ancestors = component.ancestors.take_while { |ancestor| ancestor != Phlex::SGML }
			ancestors.select! { |ancestor| Class === ancestor && !ancestor.frozen? && !compiled?(ancestor) }

			ancestors.flat_map { |ancestor| defining_files(ancestor) }.uniq.each do |path|
				compile_file(path)
			end

			ancestors.each { |ancestor| ancestor.instance_variable_set(:@__phlex_compiled__, true) }
		end
	end

	# A compiled method's source location names the generated source, which
	# its generation traces back to the file it came from.
	def self.defining_files(component)
		methods = component.instance_methods(false) + component.private_instance_methods(false) + component.protected_instance_methods(false)
		paths = methods.filter_map do |name|
			source_path = component.instance_method(name).source_location&.first
			MAP[source_path]&.path || source_path
		end
		paths << constant_source_path(component)
		paths.compact.uniq.select { |path| File.exist?(path) }
	end

	# The file the class was first defined in, unless its name no longer
	# resolves to it, as after a code reload.
	def self.constant_source_path(component)
		return unless (name = component.name)
		return unless Object.const_get(name).equal?(component)

		Object.const_source_location(name)&.first
	rescue NameError
		nil
	end

	# Why parts of the files defining the component and its Phlex ancestors are
	# left to the runtime, as Diagnostics::Diagnostic records in file order.
	# Nothing is compiled; an already compiled method is reported as such.
	def self.explain(component)
		component!(component)

		ancestors = component.ancestors.take_while { |ancestor| ancestor != Phlex::SGML }.select { |ancestor| Class === ancestor }

		ancestors.flat_map { |ancestor| defining_files(ancestor) }.uniq.flat_map do |path|
			diagnostics = Diagnostics.new(path)
			FileCompiler.new(path, diagnostics:).compile(parse(File.read(path), path))
			diagnostics.to_a
		end
	end

	# Compiles the Phlex components defined in an already-loaded file.
	def self.compile_file(path)
		unless File.exist?(path)
			raise ArgumentError, "Can’t compile #{path} because it doesn’t exist."
		end

		source = File.read(path)
		results = FileCompiler.new(path).compile(parse(source, path)).reject { |result| result.compiled_snippets.empty? }
		return if results.empty?

		program = Refract::StatementsNode.new(body: results.map { |result| wrap_in_namespace(result) })
		formatting_result = Refract::Formatter.new(starting_line: 2).format_node(program)

		compiled_path = "#{path} (compiled #{@generations += 1})"

		without_redefinition_warnings do
			eval(
				"#{magic_comments(source)}#{formatting_result.source}",
				TOPLEVEL_BINDING,
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
		end

		nil
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

	def self.wrap_in_namespace(result)
		result.namespace.reverse_each.reduce(
			Refract::StatementsNode.new(body: result.compiled_snippets)
		) do |body, scope|
			wrapped = Refract::StatementsNode.new(body: [body])

			case scope
			in Refract::ClassNode then scope.copy(body: wrapped, superclass: nil)
			in Refract::ModuleNode then scope.copy(body: wrapped)
			end
		end
	end

	module LazyCompilation
		def internal_call(...)
			if Phlex::Compiler.enabled? && !Phlex::Compiler.compiled?(self.class)
				Phlex::Compiler.compile(self.class)
			end

			super
		end
	end
end
