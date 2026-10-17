# frozen_string_literal: true

module Phlex::Kit
	KEYWORDS = Set[:BEGIN, :END].freeze
	private_constant :KEYWORDS

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

	def const_added(name)
		return if autoload?(name)

		constant = const_get(name)

		case constant
		when Class
			if constant < Phlex::SGML
				constant.include(self)

				# Defined from a string so the methods don't close over anything and
				# can be called from any Ractor. The constant is looked up on each call,
				# lexically in this kit, so core constants are written `::`-qualified.
				# BEGIN and END are valid constant names but keywords in source.
				reference = KEYWORDS.include?(name) ? "::Module.nesting.first.const_get(:#{name})" : name

				module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
					def #{name}(*args, **kwargs, &block)
						render(#{reference}.new(*args, **kwargs), &block)
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
