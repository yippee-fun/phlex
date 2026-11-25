# frozen_string_literal: true

# The methods compiled code calls for the runtime, which calls them from its
# own files. A refinement active in a component's file, or a core method
# redefined in Ruby, would change what compiled code does but not what the
# runtime does, so the compiler refuses to compile in either case.
module Phlex::Compiler::CoreCalls
	extend self

	# Receiver class => methods called on it, or nil for any that Phlex defines.
	CALLS = {
		String => %i[<< include? ascii_only? encoding valid_encoding? +@],
		Symbol => %i[name],
		Integer => %i[== > to_s],
		Float => %i[to_s],
		Hash => %i[length []],
		String.singleton_class => %i[===],
		Symbol.singleton_class => %i[===],
		Integer.singleton_class => %i[===],
		Float.singleton_class => %i[===],
		Phlex::SGML::SafeObject.singleton_class => %i[===],
		Exception.singleton_class => %i[===],
		TrueClass => %i[=== ==],
		NilClass => %i[=== ==],
		Encoding => %i[equal?],
		Set.singleton_class => %i[[]],
		Kernel => %i[block_given?],
		Kernel.singleton_class => %i[raise],
		Phlex::SGML::SafeObject => %i[to_s],
		Phlex.singleton_class => %i[__map_exception__],
		Phlex::Escape.singleton_class => %i[html_escape],
		Phlex.__attribute_cache__.singleton_class => %i[fetch append],
		Phlex::SGML::Attributes.singleton_class => nil,
		Phlex::SGML::Elements.singleton_class => nil,
		Phlex::Compiler.singleton_class => nil,
		Phlex::SGML::State => nil,
	}.freeze

	# Called on the component itself, where element methods call them from
	# the file that defines them.
	COMPONENT_CALLS = %i[block_given? __phlex_equal__? format_object __implicit_output__ __yield_content__ __text__ flush].freeze

	# Core methods implemented in C on CRuby, which a definition in Ruby replaced.
	NATIVE = [String, Symbol, Integer, Float, Hash, String.singleton_class, Symbol.singleton_class, Integer.singleton_class, Float.singleton_class, Exception.singleton_class, TrueClass, NilClass, Encoding, Kernel, Kernel.singleton_class].freeze

	# Called unbound, so a refinement module can't hide what it refines.
	REFINEMENTS = Module.instance_method(:refinements)
	TARGET = Refinement.instance_method(:target)
	INSTANCE_METHODS = Module.instance_method(:instance_methods)
	PRIVATE_INSTANCE_METHODS = Module.instance_method(:private_instance_methods)
	UNDEFINED_INSTANCE_METHODS = Module.instance_method(:undefined_instance_methods)

	# The core methods, and whether they were public, as they were when Phlex loaded.
	SUBCLASSES = Class.instance_method(:subclasses)

	# Phlex's own methods compiled code calls, whose redefinition would change
	# it but not the runtime, which doesn't call them.
	HELPERS = {
		Phlex::Compiler.singleton_class => %i[keywords escape_value symbol_value yield_component nested_attributes],
		Phlex::SGML::Attributes.singleton_class => %i[attribute reference_attribute generate_attributes],
	}.freeze

	PHLEX_PATH = "#{File.dirname(__dir__)}/"

	ORIGINALS = CALLS.merge(HELPERS).select { |_receiver, names| names }.flat_map { |receiver, names|
		names.filter_map do |name|
			if receiver.method_defined?(name) || receiver.private_method_defined?(name)
				[[receiver, name], [receiver.instance_method(name), receiver.public_method_defined?(name)]]
			end
		end
	}.to_h.freeze

	# The first refined method compiled code calls, as "Class#method".
	def refined(modules, component, descendants = [])
		calls = CALLS.merge([component, *descendants].to_h { |receiver| [receiver, COMPONENT_CALLS] })

		modules.each do |mod|
			REFINEMENTS.bind_call(mod).each do |refinement|
				target = TARGET.bind_call(refinement)
				names = INSTANCE_METHODS.bind_call(refinement, false) | PRIVATE_INSTANCE_METHODS.bind_call(refinement, false) |
					UNDEFINED_INSTANCE_METHODS.bind_call(refinement)

				calls.each do |receiver, called|
					names.each do |name|
						return "#{target.inspect}##{name}" if affects?(receiver, called, target, name)
					end
				end
			end
		end

		nil
	end

	# The first core method compiled code calls that's been redefined, or had
	# its visibility changed, since Phlex loaded, or that's defined in Ruby
	# where CRuby implements it in C.
	def redefined
		ORIGINALS.each do |(receiver, name), (original, public)|
			method = receiver.instance_method(name)
			changed = method != original || receiver.public_method_defined?(name) != public ||
				(RUBY_ENGINE == "ruby" && NATIVE.include?(receiver) && defined_in_ruby?(method)) ||
				(HELPERS[receiver]&.include?(name) && !defined_by_phlex?(method))
			return "#{receiver.inspect}##{name}" if changed
		rescue NameError
			return "#{receiver.inspect}##{name}"
		end

		nil
	end

	# The snapshot is taken when the compiler loads, which may be after an
	# override, so helpers must also still be Phlex's own, or its C extension's.
	private def defined_by_phlex?(method)
		if (path = method.source_location&.first)
			path.start_with?(PHLEX_PATH)
		else
			defined?(Phlex::Native::Attributes) && method.owner.equal?(Phlex::Native::Attributes)
		end
	end

	# Whether a core method is the original, as far as the engine can tell.
	def native?(method)
		RUBY_ENGINE != "ruby" || !defined_in_ruby?(method)
	end

	# CRuby writes some core methods in Ruby, under `<internal:…>` paths.
	private def defined_in_ruby?(method)
		(path = method.source_location&.first) && !path.start_with?("<internal:")
	end

	# A refinement applies to a call when its target comes no later in the
	# receiver's ancestors than where the method would otherwise be found. A
	# refinement of a subclass applies too, as the receiver may be one, except
	# for a class method, called on that class.
	private def affects?(receiver, called, target, name)
		return false unless called.nil? || called.include?(name)

		if receiver.ancestors.include?(target)
			found_after?(receiver, target, name, missing: !called.nil?, phlex_only: called.nil?)
		elsif receiver.singleton_class? || !(Module === target)
			false
		elsif called.nil?
			# Only a method Phlex defines is called on a subclass of a Phlex receiver.
			descends?(receiver, target) && (receiver.method_defined?(name) || receiver.private_method_defined?(name)) && phlex?(receiver.instance_method(name).owner)
		else
			descends?(receiver, target)
		end
	end

	# Whether the target is a subclass of the receiver, or mixed into one, so
	# a value compiled code receives could be one. A module could also be
	# extended onto any one value.
	private def descends?(receiver, target)
		return true unless Class === target
		return true if target.ancestors.include?(receiver)
		return false unless Class === receiver

		SUBCLASSES.bind_call(receiver).any? { |subclass| subclass.ancestors.include?(target) || descends?(subclass, target) }
	end

	# A named method compiled code calls that's missing is affected by a
	# refinement defining it; any other missing method isn't called. Where any
	# method counts, only those Phlex defines are called.
	private def found_after?(receiver, target, name, missing:, phlex_only:)
		owner = receiver.instance_method(name).owner
		return false if phlex_only && !phlex?(owner)

		ancestors = receiver.ancestors
		ancestors.index(target) <= ancestors.index(owner)
	rescue NameError
		missing
	end

	# A class method's owner is the singleton class of the module defining it.
	private def phlex?(owner)
		owner = owner.attached_object if owner.singleton_class?
		Module === owner && owner.name&.start_with?("Phlex")
	end
end
