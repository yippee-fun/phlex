# frozen_string_literal: true

module Phlex::Kit
	module LazyLoader
		def method_missing(name, ...)
			mod = self.class

			if name[0] == name[0].upcase && mod.constants.include?(name) && mod.const_get(name) && methods.include?(name)
				public_send(name, ...)
			else
				super
			end
		end

		def respond_to_missing?(name, include_private = false)
			mod = self.class

			(name[0] == name[0].upcase && mod.constants.include?(name) && mod.const_get(name) && methods.include?(name)) || super
		end
	end

	def self.extended(mod)
		case mod
		when Class
			raise Phlex::ArgumentError.new(<<~MESSAGE)
				`Phlex::Kit` was extended into #{mod.name}.

				You should only extend modules with `Phlex::Kit` as it is not compatible with classes.
			MESSAGE
		else
			mod.include(LazyLoader)
		end
	end

	def method_missing(name, ...)
		if name[0] == name[0].upcase && constants.include?(name) && const_get(name) && methods.include?(name)
			public_send(name, ...)
		else
			super
		end
	end

	def respond_to_missing?(name, include_private = false)
		(name[0] == name[0].upcase && constants.include?(name) && const_get(name) && methods.include?(name)) || super
	end

	NAME = Module.instance_method(:name)
	CONST_GET = Module.instance_method(:const_get)

	# The constants a method can reach a kit by, one `const_get` at a time,
	# which a module nested in an anonymous one doesn't have. Each is looked
	# up with `const_get`, since a constant can be made private after its
	# kit's components are defined, and compiled code makes the same calls.
	# Defined here rather than on the kit, whose own methods could replace it.
	def self.named_path(kit)
		return unless (name = NAME.bind_call(kit))

		path = name.split("::").map(&:to_sym)
		path if path.reduce(Object) { |namespace, constant| CONST_GET.bind_call(namespace, constant, false) }.equal?(kit)
	rescue NameError, TypeError
		nil
	end

	def const_added(name)
		return if autoload?(name)

		constant = const_get(name)

		case constant
		when Class
			if constant < Phlex::SGML
				constant.include(self)

				# Defined from a string so they can be called from any Ractor. A named
				# kit is looked up by its name, as compiled code does, so a reloaded
				# kit's component is found even from a component that wasn't reloaded.
				reference = if (path = Phlex::Kit.named_path(self))
					["::Object", *[*path, name].map { |constant| "const_get(:#{constant})" }].join(".")
				elsif name in :BEGIN | :END
					"::Module.nesting.first.const_get(:#{name})"
				else
					name
				end

				module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
					def #{name}(*, **, &)
						render(#{reference}.new(*, **), &)
					end

					def self.#{name}(*args, **kwargs, &block)
						component = ::Thread.current[:__phlex_component__]
						if component
							component.instance_exec do
								render(#{reference}.new(*args, **kwargs), &block)
							end
						else
							raise "You can't call `#{name}' outside of a Phlex rendering context."
						end
					end
				RUBY
			end
		when Module
			constant.extend(Phlex::Kit)
		end

		super
	end
end
