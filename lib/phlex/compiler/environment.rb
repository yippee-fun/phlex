# frozen_string_literal: true

# What the compiler knows about the class whose methods it's compiling: which
# bare calls are elements or helpers it can inline, which of those a loaded
# subclass overrides, and whether a bare `Set` in the class body is the
# standard library's. Built once per class body and shared by its methods.
class Phlex::Compiler::Environment
	ELEMENTS_SOURCE_PATH = Phlex::SGML::Elements.instance_method(:register_element).source_location[0]
	HELPER_OWNERS = Set[Phlex::SGML, Phlex::HTML, Phlex::SVG].freeze
	SGML_SOURCE_PATH = Phlex::SGML.instance_method(:plain).source_location[0]
	HELPER_SOURCE_PATHS = Set[
		SGML_SOURCE_PATH,
		Phlex::HTML.instance_method(:doctype).source_location[0],
	].freeze

	Element = Data.define(:tag, :void)

	# What Phlex::HTML#svg's Phlex::SVG runs around its block, which compiled
	# code skips when it inlines the block.
	SVG_RENDER = %i[initialize render? before_template around_template after_template view_template internal_call __yield_content__ __implicit_output__].freeze

	# The class methods `render Phlex::SVG.new` calls.
	SVG_CLASS_METHODS = %i[new allocate ===].freeze

	# The element and helper names whose implementation compiled methods have
	# baked in, by inlining them or by relying on what they return.
	attr_reader :inlined

	# The Phlex::SVG methods an inlined svg block relies on.
	attr_reader :inlined_svg

	# With `inline: false` nothing is recognised, so every method compiles to
	# its original definition. Used to restore a class before it's frozen.
	def initialize(component, standard_set: standard_set_on?(component), method_resolver: Phlex::UNBOUND_INSTANCE_METHOD_METHOD.method(:bind_call), inline: true)
		@component = component
		@standard_set = standard_set
		@method_resolver = method_resolver
		@inline = inline
		@elements = {}
		@helpers = {}
		@inlined = Set.new
		@inlined_svg = Set.new
	end

	def standard_set? = @standard_set

	# The element a bare call to the method renders, if it's a registered
	# element that no loaded descendant overrides.
	def element(name)
		return unless @inline && kernel_block_given?
		return @elements[name] if @elements.key?(name)

		@elements[name] = resolve_element(name)
	end

	# Whether a bare call to the method reaches one of the SGML helpers, such
	# as `plain`, that no loaded descendant overrides.
	def helper?(name)
		return false unless @inline && kernel_block_given?
		return @helpers[name] if @helpers.key?(name)

		@helpers[name] = resolve_helper(name)
	end

	# An environment for the Phlex::SVG that `svg` renders around its block,
	# if the block can be inlined: while svg is Phlex::HTML's, its super is
	# the registered element, and Phlex::SVG renders as Phlex wrote it.
	def svg_environment
		return @svg_environment if defined?(@svg_environment)

		@svg_environment = (Phlex::Compiler::Environment.new(Phlex::SVG, standard_set: @standard_set, method_resolver: @method_resolver) if inline_svg?)
	end

	private def inline_svg?
		return false unless helper?(:svg) && helper?(:render) && (element = instance_method(:svg).super_method)
		return false unless element.source_location&.first == ELEMENTS_SOURCE_PATH && element.original_name == :svg
		return false unless element.owner.respond_to?(:__element_registry__)

		registry = element.owner.__element_registry__
		return false unless registry.elements[:svg] == "svg" && !registry.void_elements.key?(:svg)
		return false unless sgml_new?

		SVG_RENDER.all? do |name|
			method = instance_method(name, Phlex::SVG)
			# Lazy compilation compiles a component before rendering it as before.
			method = method.super_method if method&.owner == Phlex::Compiler::LazyCompilation

			method && method.original_name == name && (
				(method.owner == Phlex::SGML && method.source_location&.first == SGML_SOURCE_PATH) ||
				(name == :initialize && method.owner == BasicObject)
			)
		end
	end

	# Whether `render Phlex::SVG.new` builds and recognises the SVG as Phlex wrote it.
	private def sgml_new?
		(new = instance_method(:new, Phlex::SVG.singleton_class)) && new.owner == Phlex::SGML.singleton_class &&
			new.original_name == :new && new.source_location&.first == SGML_SOURCE_PATH &&
			instance_method(:allocate, Phlex::SVG.singleton_class)&.owner == Class &&
			instance_method(:===, Phlex::SGML.singleton_class)&.owner == Module
	end

	# An element called on an explicit receiver, so only if it's public.
	def public_element(name)
		element(name) if @component.public_method_defined?(name)
	end

	# Element and helper methods ask block_given? whether they were given a
	# block, so they're only inlined while it's Kernel's.
	def kernel_block_given?
		return @kernel_block_given if defined?(@kernel_block_given)

		@kernel_block_given = standard?(:block_given?, Kernel)
	end

	private def standard?(name, owner)
		(method = instance_method(name)) && method.owner == owner && method.original_name == name && !overridden_by_descendant?(name, owner)
	end

	# Without the lexical scopes, the class and its ancestors are the best guess.
	private def standard_set_on?(component)
		component.const_get(:Set).equal?(::Set)
	rescue NameError
		false
	end

	private def resolve_element(name)
		return unless (method = instance_method(name))

		owner = method.owner
		return unless owner.respond_to?(:__element_registry__)
		return unless method.source_location&.first == ELEMENTS_SOURCE_PATH && method.original_name == name

		registry = owner.__element_registry__
		return unless (tag = registry.elements[name])
		return if overridden_by_descendant?(name, owner)

		Element.new(tag:, void: registry.void_elements.key?(name))
	end

	private def resolve_helper(name)
		return false unless (method = instance_method(name))

		HELPER_OWNERS.include?(method.owner) && method.original_name == name &&
			HELPER_SOURCE_PATHS.include?(method.source_location&.first) &&
			!overridden_by_descendant?(name, method.owner)
	end

	# A compiled method is inherited, so it must not bake in a method that a
	# loaded subclass overrides.
	private def overridden_by_descendant?(name, owner)
		descendants.any? do |descendant|
			instance_method(name, descendant)&.owner != owner
		end
	end

	private def descendants
		@descendants ||= Phlex::Compiler.descendants_of(@component)
	end

	# The resolver runs in the file's lexical scope, where a refinement of
	# UnboundMethod#bind or Method#call could intercept it. Anything but the
	# named method counts as unresolved, which only keeps the call as it is.
	private def instance_method(name, component = @component)
		method = @method_resolver.call(component, name)
		method if UnboundMethod === method && method.name == name
	rescue
		nil
	end
end
