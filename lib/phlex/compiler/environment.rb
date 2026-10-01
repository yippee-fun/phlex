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

	attr_reader :component

	# The element and helper names whose implementation compiled methods have
	# baked in, by inlining them or by relying on what they return.
	attr_reader :inlined

	def initialize(component, standard_set: standard_set_on?(component))
		@component = component
		@standard_set = standard_set
		@elements = {}
		@helpers = {}
		@inlined = Set.new
	end

	def standard_set? = @standard_set

	# The element a bare call to the method renders, if it's a registered
	# element that no loaded descendant overrides.
	def element(name)
		return @elements[name] if @elements.key?(name)

		@elements[name] = resolve_element(name)
	end

	# Whether a bare call to the method reaches one of the SGML helpers, such
	# as `plain`, that no loaded descendant overrides.
	def helper?(name)
		return @helpers[name] if @helpers.key?(name)

		@helpers[name] = resolve_helper(name)
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
		return unless owner.respond_to?(:__registered_elements__)
		return unless method.source_location&.first == ELEMENTS_SOURCE_PATH
		return unless (tag = owner.__registered_elements__[name])
		return if overridden_by_descendant?(name, owner)

		Element.new(tag:, void: owner.__registered_void_elements__.key?(name))
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
			Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(descendant, name).owner != owner
		rescue NameError
			true
		end
	end

	private def descendants
		@descendants ||= descendants_of(@component)
	end

	private def descendants_of(component)
		component.subclasses.flat_map { |subclass| [subclass, *descendants_of(subclass)] }
	end

	private def instance_method(name)
		Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, name)
	rescue NameError
		nil
	end
end
