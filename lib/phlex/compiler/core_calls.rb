# frozen_string_literal: true

# The methods compiled code calls for the runtime, which calls them from its
# own files. A refinement active in a component's file, or a core method
# redefined in Ruby, would change what compiled code does but not what the
# runtime does, so the compiler refuses to compile in either case.
module Phlex::Compiler::CoreCalls
	extend self

	# Receiver class => methods called on it, or nil for any.
	CALLS = {
		String => %i[<< include? ascii_only? encoding valid_encoding? +@],
		Integer => %i[==],
		String.singleton_class => %i[===],
		Symbol.singleton_class => %i[===],
		Phlex::SGML::SafeObject.singleton_class => %i[===],
		TrueClass => %i[equal?],
		NilClass => %i[equal?],
		Encoding => %i[equal?],
		Set.singleton_class => %i[[]],
		Kernel.singleton_class => %i[raise],
		Phlex.singleton_class => %i[__map_exception__],
		Phlex::Escape.singleton_class => %i[html_escape],
		Phlex::SGML::Attributes.singleton_class => nil,
		Phlex::SGML::Elements.singleton_class => nil,
		Phlex::Compiler.singleton_class => nil,
		Phlex::SGML::State => nil,
		Phlex::AttributeCache => nil,
	}.freeze

	# Called on the component itself, where element methods call them from
	# the file that defines them.
	COMPONENT_CALLS = %i[block_given? equal? format_object __implicit_output__ __yield_content__ flush].freeze

	# Core methods implemented in C, which a Ruby redefinition would replace.
	NATIVE = [String, Integer, String.singleton_class, Symbol.singleton_class, TrueClass, NilClass, Encoding, Kernel.singleton_class].freeze

	# The first refined method compiled code calls, as "Class#method".
	def refined(modules, component)
		calls = CALLS.merge(component => COMPONENT_CALLS)

		modules.each do |mod|
			mod.refinements.each do |refinement|
				names = refinement.instance_methods(false) | refinement.private_instance_methods(false)

				calls.each do |receiver, called|
					next unless receiver.ancestors.include?(refinement.target)

					name = called ? (called & names).first : names.first
					return "#{refinement.target.inspect}##{name}" if name
				end
			end
		end

		nil
	end

	# The first core method compiled code calls that's been redefined in Ruby.
	def redefined
		return unless RUBY_ENGINE == "ruby"

		NATIVE.each do |receiver|
			CALLS.fetch(receiver).each do |name|
				method = receiver.instance_method(name)
				return "#{method.owner.inspect}##{name}" if method.source_location
			end
		end

		nil
	end
end
