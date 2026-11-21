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
# line, a local or bare call named like a local the compiler generates
# (`__phlex_…`), a file edited since it was loaded, a refinement in the file
# of a method compiled code calls for the runtime, such as String#include?,
# or such a core method redefined in Ruby, and redefining an inlined element
# or helper on a single instance with `extend` or a singleton method.
# Redefining one on a class or by including a module recompiles whatever
# inlined it.
#
# Seven differences remain, all deliberate:
# - Changing what an inlined element or helper resolves to through a module
#   already mixed into a compiled component, or into Phlex::SVG for an inlined
#   svg block, isn't seen: defining, removing or undefining it on that module,
#   changing its visibility there, or mixing another module into it. Nor is
#   changing the visibility of a method where it's defined, such as `new` on
#   Phlex::SGML. Call `Phlex::Compiler.recompile` on each class whose methods
#   inlined it. A method already running when one is redefined finishes as
#   compiled.
# - Attributes with literal keys are serialised without the attribute cache, so
#   a value's `to_s`, `to_h` or `iso8601` runs on every render rather than once
#   per distinct set of attributes, and its `hash` isn't called.
# - Compiled code appends the text of neighbouring elements together and reads
#   the state once per method. When an append itself fails, because the buffer
#   is frozen or holds text in an encoding the new text can't join, the partial
#   output, the exception raised and its `cause` can differ from element
#   methods appending one by one. A buffer switched mid-element, by a Fiber
#   suspended inside `capture`, and a method that started before rendering,
#   can see a different buffer, and the buffer itself passed as an attribute
#   value is read after the attribute's name is appended to it. Whether to
#   render is checked at each append, where an element method checks once,
#   which only matters to code starting a fragment mid-element. A State
#   subclass overriding its methods sees them called a different number of
#   times, and an inlined svg block skips the State and core methods the
#   runtime calls to render its Phlex::SVG, such as `around_render` and
#   `Thread#[]=`.
# - Static text and attributes are escaped and serialised once, when
#   compiling, outside `Regexp.timeout`, and so are references whose prefix
#   is known. A core method compiled code calls that's redefined after
#   compiling isn't noticed. A String subclass whose `gsub` returns something
#   other than a String, which the serialiser's own paths treat differently,
#   renders as its path for names it's seen before does.
# - Method#source_location of a compiled method names the generated source;
#   exceptions are mapped back to the real file. `local_variables` and
#   `binding` in a compiled method also see the compiler's `__phlex_` locals.
# - A block passed to a method the compiler doesn't know is compiled alongside
#   a copy of the original, used when the block runs with another `self`. A
#   literal Ruby reuses on each evaluation, such as a regular expression or a
#   range, is a different object in each copy.
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
	Probe = Data.define(:component, :set, :method_resolver, :refinements)

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

	# Compiled code builds splatted attributes with this rather than a Hash
	# literal, since before Ruby 3.4 `**nil` is only allowed in a call.
	def self.keywords(**keywords) = keywords

	# Compiled code escapes quotes with this, so the match data gsub sets stays
	# out of the component's method, as at runtime.
	def self.escape_quotes(value) = value.gsub('"', "&quot;")

	# Compiled code writes a Symbol attribute value with this, as the serialiser does.
	def self.symbol_value(symbol)
		name = symbol.name
		name = name.tr("_", "-") if name.include?("_")
		name.include?('"') ? name.gsub('"', "&quot;") : name
	end

	# Compiled code yields to an element's block with this when the block can't
	# be inlined, as the element method yields to it.
	def self.yield_component(component) = yield(component)

	# Compiled code serialises one entry of a nested attribute hash with this,
	# as the runtime does within the whole hash.
	def self.nested_attributes(key, value, base)
		buffer = +""
		Phlex::SGML::Attributes.generate_nested_attributes({ key => value }, base, buffer)
		buffer
	end

	# Compile each component on its first render. A component that fails to
	# compile is reported to `on_failure` once and keeps rendering uncompiled,
	# so a compiler bug costs speed, never a page.
	#
	# Only the main Ractor compiles. Other Ractors render a component as they
	# find it, without waiting for a compilation in progress, so compile with
	# `Phlex::Compiler.compile` before starting them.
	def self.enable!(on_failure: DEFAULT_FAILURE_HANDLER)
		# Prepended under the lock, so it isn't taken for a change to what's been
		# inlined: it only compiles a component before rendering it as before.
		MUTEX.synchronize { Phlex::SGML.prepend(LazyCompilation) } unless Phlex::SGML < LazyCompilation
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
	# renders racing each other still compile and report once, and a render
	# that starts while a recompilation holds it waits for the new methods.
	# The handler runs outside it, since it may well render something.
	def self.compile_on_first_render(component)
		return unless Phlex.__main_ractor__?

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

		parse_result = Prism.parse(without_byte_order_mark(File.read(path)), filepath: path)
		file_compiler = FileCompiler.new(path, targets: targets(path, components, recompile:), recompile:, inline:)
		results = file_compiler.compile(Refract::Converter.new.visit(parse_result.value)).reject { |result| result.compiled_snippets.empty? }
		return if results.empty?

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

		without_redefinition_warnings do
			eval(
				"#{magic_comments(parse_result)}#{formatting_result.source}",
				scope,
				compiled_path,
				1
			)
		end

		results.each do |result|
			result.visibilities.each do |name, visibility|
				result.component.__send__(visibility, name) unless visibility == :public
			end

			inlined = result.component.instance_variable_get(:@__phlex_inlined__) || Set.new
			result.component.instance_variable_set(:@__phlex_inlined__, (inlined | result.inlined).freeze)

			inlined_svg = result.component.instance_variable_get(:@__phlex_inlined_svg__) || Set.new
			result.component.instance_variable_set(:@__phlex_inlined_svg__, (inlined_svg | result.inlined_svg).freeze)
		end

		nil
	end

	# Called by Phlex::SGML when methods are defined on, removed from or mixed
	# into a class or singleton class. A compiled class above or below it that
	# inlined one of them is recompiled, and with the change now loaded it
	# stops inlining that name, so the change takes effect just as it would
	# have uncompiled. A class that inlined an svg block relying on one of them
	# on Phlex::SVG is recompiled too. An override on a single instance can't
	# be compiled for, so it's refused.
	def self.inlining_changed(target, names)
		return if Phlex.__main_ractor__? && MUTEX.owned?

		related = target.singleton_class? ? target.ancestors : target.ancestors + descendants_of(target)
		affected = related.select do |klass|
			(inlined = klass.instance_variable_get(:@__phlex_inlined__)) && names.any? { |name| inlined.include?(name) }
		end

		if !target.singleton_class? && Phlex::SVG <= target
			affected |= loaded_components.select do |klass|
				(inlined = klass.instance_variable_get(:@__phlex_inlined_svg__)) && names.any? { |name| inlined.include?(name) }
			end
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
			component.remove_instance_variable(:@__phlex_inlined_svg__) if component.instance_variable_defined?(:@__phlex_inlined_svg__)

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
	# inside but a call reporting the class reached, what `Set` names there and
	# the refinements active there. The method resolver captures the file's
	# refinements, so element and helper lookup uses the same lexical scope as
	# the compiled definitions. The statements are copied without their
	# superclasses, so they only reopen.
	# Bind and call separately: TruffleRuby's bind_call loses the caller's refinements.
	def self.probe(namespace, usings: [])
		report = parse(<<~RUBY, PROBE_PATH).statements.body.first
			::Phlex::Compiler.__probe__(self, defined?(Set) && Set, ->(component, name) {
				::Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind(component).call(name)
			}, ::Module.used_modules)
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

	def self.__probe__(component, set, method_resolver, refinements)
		Thread.current[:__phlex_compiler_probe__] = Probe.new(component:, set:, method_resolver:, refinements:)
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

	module LazyCompilation
		def internal_call(...)
			Phlex::Compiler.compile_on_first_render(self.class) if Phlex::Compiler.enabled?

			super
		end
	end
end
