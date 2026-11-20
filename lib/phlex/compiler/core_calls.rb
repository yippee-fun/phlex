# frozen_string_literal: true

# The methods compiled code calls for the runtime, which calls them from its
# own files. A refinement active in a component's file, or a core method
# redefined in Ruby, would change what compiled code does but not what the
# runtime does, so the compiler refuses to compile in either case.
module Phlex::Compiler::CoreCalls
	extend self

	# Receiver class => methods called on it, or nil for any it defines.
	CALLS = {
		String => %i[<< include? ascii_only? encoding valid_encoding? +@],
		Symbol => %i[name],
		Integer => %i[==],
		String.singleton_class => %i[===],
		Symbol.singleton_class => %i[===],
		Phlex::SGML::SafeObject.singleton_class => %i[===],
		Exception.singleton_class => %i[===],
		TrueClass => %i[===],
		NilClass => %i[===],
		Encoding => %i[equal?],
		Set.singleton_class => %i[[]],
		Kernel.singleton_class => %i[raise],
		Phlex::SGML::SafeObject => %i[to_s],
		Phlex.singleton_class => %i[__map_exception__],
		Phlex::Escape.singleton_class => %i[html_escape],
		Phlex::SGML::Attributes.singleton_class => nil,
		Phlex::SGML::Elements.singleton_class => nil,
		Phlex::Compiler.singleton_class => nil,
		Phlex::SGML::State => nil,
		Phlex::AttributeCache => nil,
		Phlex.__attribute_cache__.class => nil,
	}.freeze

	# Called on the component itself, where element methods call them from
	# the file that defines them.
	COMPONENT_CALLS = %i[block_given? __phlex_equal__? format_object __implicit_output__ __yield_content__ __text__ flush].freeze

	# Core methods implemented in C on CRuby, which a definition in Ruby replaced.
	NATIVE = [String, Symbol, Integer, String.singleton_class, Symbol.singleton_class, Exception.singleton_class, TrueClass, NilClass, Encoding, Kernel.singleton_class].freeze

	# The core methods as they were when Phlex loaded.
	ORIGINALS = CALLS.select { |_receiver, names| names }.flat_map { |receiver, names|
		names.filter_map { |name| [[receiver, name], receiver.instance_method(name)] if receiver.method_defined?(name) }
	}.to_h.freeze

	# The first refined method compiled code calls, as "Class#method".
	def refined(modules, component)
		calls = CALLS.merge(component => COMPONENT_CALLS)

		modules.each do |mod|
			mod.refinements.each do |refinement|
				target = refinement.target
				names = refinement.instance_methods(false) | refinement.private_instance_methods(false)

				calls.each do |receiver, called|
					names.each do |name|
						return "#{target.inspect}##{name}" if affects?(receiver, called, target, name)
					end
				end
			end
		end

		nil
	end

	# The first core method compiled code calls that's been redefined since
	# Phlex loaded, or in Ruby where CRuby implements it in C.
	def redefined
		ORIGINALS.each do |(receiver, name), original|
			method = receiver.instance_method(name)
			changed = method != original || (RUBY_ENGINE == "ruby" && NATIVE.include?(receiver) && defined_in_ruby?(method))
			return "#{receiver.inspect}##{name}" if changed
		rescue NameError
			return "#{receiver.inspect}##{name}"
		end

		nil
	end

	# CRuby writes some core methods in Ruby, under `<internal:…>` paths.
	private def defined_in_ruby?(method)
		(path = method.source_location&.first) && !path.start_with?("<internal:")
	end

	# A refinement of the receiver or a subclass applies to the calls it
	# names. One of an ancestor only applies where the method would otherwise
	# be found at or above that ancestor.
	private def affects?(receiver, called, target, name)
		if Module === target && target.ancestors.include?(receiver)
			called.nil? || called.include?(name)
		elsif receiver.ancestors.include?(target)
			(called.nil? || called.include?(name)) && found_above?(receiver, target, name, missing: !called.nil?)
		else
			false
		end
	end

	# A named method compiled code calls that's missing is affected by a
	# refinement defining it; any other missing method isn't called.
	private def found_above?(receiver, target, name, missing:)
		owner = receiver.instance_method(name).owner
		target.ancestors.include?(owner)
	rescue NameError
		missing
	end
end
