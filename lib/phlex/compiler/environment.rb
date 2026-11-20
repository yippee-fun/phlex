# frozen_string_literal: true

# What the compiler knows about the class whose methods it's compiling: which
# bare calls are elements or helpers it can inline, which of those a loaded
# subclass overrides, and whether a bare `Set` in the class body is the
# standard library's. Built once per class body and shared by its methods.
class Phlex::Compiler::Environment
	ELEMENTS_SOURCE_PATH = Phlex::SGML::Elements.instance_method(:register_element).source_location[0]
	HELPER_OWNERS = Set[Phlex::SGML, Phlex::HTML, Phlex::SVG].freeze
	HELPER_SOURCE_PATHS = Set[
		Phlex::SGML.instance_method(:plain).source_location[0],
		Phlex::HTML.instance_method(:doctype).source_location[0],
	].freeze

	Element = Data.define(:tag, :void)

	# The element and helper names whose implementation compiled methods have
	# baked in, by inlining them or by relying on what they return.
	attr_reader :inlined

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

	# Element and helper methods ask block_given? whether they were given a
	# block, so they're only inlined while it's Kernel's.
	def kernel_block_given?
		return @kernel_block_given if defined?(@kernel_block_given)

		@kernel_block_given = standard?(:block_given?, Kernel)
	end

	private def standard?(name, owner)
		(method = instance_method(name)) && method.owner == owner && !overridden_by_descendant?(name, owner)
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
		return unless method.source_location&.first == ELEMENTS_SOURCE_PATH

		registry = owner.__element_registry__
		return unless (tag = registry.elements[name])
		return if overridden_by_descendant?(name, owner)

		Element.new(tag:, void: registry.void_elements.key?(name))
	end

	private def resolve_helper(name)
		return false unless (method = instance_method(name))

		HELPER_OWNERS.include?(method.owner) &&
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
