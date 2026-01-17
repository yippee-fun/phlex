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

	def const_added(name)
		return if autoload?(name)

		me = self
		constant = const_get(name)

		case constant
		when Class
			if constant < Phlex::SGML
				constant.include(me)

				constant = nil

				define_method(name) do |*args, **kwargs, &block|
					constant = me.const_get(name)
					render(constant.new(*args, **kwargs), &block)
				end

				define_singleton_method(name) do |*args, **kwargs, &block|
					component = Thread.current[:__phlex_component__]
					if component
						component.instance_exec do
							constant = me.const_get(name)
							render(constant.new(*args, **kwargs), &block)
						end
					else
						raise "You can't call `#{name}' outside of a Phlex rendering context."
					end
				end
			end
		when Module
			constant.extend(Phlex::Kit)
		end

		super
	end
end
