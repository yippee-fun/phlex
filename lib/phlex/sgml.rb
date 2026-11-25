# frozen_string_literal: true

# **Standard Generalized Markup Language** for behaviour common to {HTML} and {SVG}.
class Phlex::SGML
	include Phlex::Helpers

	class << self
		# Render the view to a String. Arguments are delegated to {.new}.
		def call(...)
			new(...).call
		end

		# Create a new instance of the component.
		# @note The block will not be delegated to {#initialize}. Instead, it will be sent to {#view_template} when rendering.
		def new(*, **, &block)
			object = allocate
			object.__send__(:initialize, *, **)
			object.instance_variable_set(:@_content_block, block) if block
			object
		end
	end

	def view_template
		if block_given?
			yield
		else
			plain "Phlex Warning: Your `#{self.class.name}` class doesn't define a `view_template` method. If you are upgrading to Phlex 2.x make sure to rename your `template` method to `view_template`. See: https://beta.phlex.fun/guides/v2-upgrade.html"
		end
	end

	def to_proc
		proc { |c| c.render(self) }
	end

	# Components can only be rendered once, because Phlex can't reset their instance variables. Pass `rerenderable: true` to allow the component to be rendered again.
	def call(buffer = +"", context: {}, fragments: nil, rerenderable: false, &)
		state = Phlex::SGML::State.new(
			user_context: context,
			output_buffer: buffer,
			fragments: fragments&.to_set(&:to_s),
		)

		internal_call(parent: nil, state:, &)

		state.output_buffer << state.buffer
	ensure
		@_state = nil if rerenderable && @_state.equal?(state)
	end

	def internal_call(parent: nil, state: nil, &block)
		if @_state
			raise Phlex::DoubleRenderError.new(
				"You can't render a #{self.class.name} more than once. To render a component more than once, pass `rerenderable: true` to `call` each time you render it."
			)
		end

		@_state = state

		return "" unless render?

		block ||= @_content_block

		begin
			previous_phlex_component = Thread.current[:__phlex_component__]
			Thread.current[:__phlex_component__] = self

			state.around_render(self) do
				before_template(&block)

				around_template do
					if block
						view_template do |*args|
							if args.length > 0
								__yield_content_with_args__(*args, &block)
							else
								__yield_content__(&block)
							end
						end
					else
						view_template
					end
				end

				after_template(&block)
			end
		ensure
			Thread.current[:__phlex_component__] = previous_phlex_component
		end
	end

	def context
		if rendering?
			@_state.user_context
		else
			raise Phlex::ArgumentError.new(<<~MESSAGE)
				You can’t access the context before the component has started rendering.
			MESSAGE
		end
	end

	# Returns `false` before rendering and `true` once the component has started rendering.
	# It will not reset back to false after rendering, unless the component was rendered with `rerenderable: true`.
	def rendering?
		!!@_state
	end

	# Output plain text.
	def plain(content)
		raise Phlex::ArgumentError.new("plain does not accept a block.") if block_given?

		unless __text__(content)
			raise Phlex::ArgumentError.new("You've passed an object to plain that is not handled by format_object. See https://rubydoc.info/gems/phlex/Phlex/SGML#format_object-instance_method for more information")
		end

		nil
	end

	# Output a single space character. If a block is given, a space will be output before and after the block.
	def whitespace(&)
		state = @_state

		unless state.should_render?
			yield(self) if block_given?
			return nil
		end

		buffer = state.buffer

		buffer << " "

		if block_given?
			__yield_content__(&)
			buffer << " "
		end

		nil
	end

	# Wrap the output in an HTML comment.
	#
	# [MDN Docs](https://developer.mozilla.org/en-US/docs/Web/HTML/Comments)
	def comment(&)
		state = @_state

		unless state.should_render?
			yield(self) if block_given?
			return nil
		end

		buffer = state.buffer

		buffer << "<!-- "
		__yield_content__(&)
		buffer << " -->"

		nil
	end

	# Output the given safe object as-is. You may need to use `safe` to mark a string as a safe object.
	def raw(content)
		case content
		when Phlex::SGML::SafeObject
			state = @_state
			return unless state.should_render?

			state.append(content.to_s)
		when nil, "" # do nothing
		else
			raise Phlex::ArgumentError.new("You passed an unsafe object to `raw`.")
		end

		nil
	end

	# Capture the output of the block and returns it as a string.
	def capture(*args, &block)
		return "" unless block

		if args.length > 0
			@_state.capture { __yield_content_with_args__(*args, &block) }
		else
			@_state.capture { __yield_content__(&block) }
		end
	end

	# Define a named fragment that can be selectively rendered.
	def fragment(name)
		name = name.to_s
		state = @_state
		state.begin_fragment(name)
		completed = false
		begin
			yield
			completed = true
		ensure
			state.end_fragment(name, halt: completed)
		end
		nil
	end

	# Mark the given string as safe for HTML output.
	def safe(value)
		case value
		when String
			Phlex::SGML::SafeValue.new(value)
		else
			raise Phlex::ArgumentError.new("Expected a String.")
		end
	end

	alias_method :🦺, :safe

	# Flush the current state to the output buffer.
	def flush
		@_state.flush
	end

	def render(renderable = nil, &)
		case renderable
		when Phlex::SGML
			renderable.internal_call(state: @_state, parent: self, &)
		when Class
			if renderable < Phlex::SGML
				render(renderable.new, &)
			else
				raise Phlex::ArgumentError.new("You can't render a #{renderable.inspect}.")
			end
		when Enumerable
			renderable.each { |r| render(r, &) }
		when Proc, Method
			if renderable.arity == 0
				__yield_content_with_no_yield_args__(&renderable)
			else
				__yield_content__(&renderable)
			end
		when String
			plain(renderable)
		when nil
			__yield_content__(&) if block_given?
		else
			raise Phlex::ArgumentError.new("You can't render a #{renderable.inspect}.")
		end

		nil
	end

	# Cache a block of content.
	#
	# ```ruby
	# @products.each do |product|
	#   cache product do
	#     h1 { product.name }
	#   end
	# end
	# ```
	def cache(*cache_key, **, &content)
		location = caller_locations(1, 1)[0]

		full_key = [
			app_version_key,                                   # invalidates the key when deploying new code in case of changes
			self.class.name,                                   # prevents collisions between classes
			(self.class.object_id if enable_cache_reloading?), # enables reloading
			location.base_label,                               # prevents collisions between different methods
			Phlex.__source_line__(location),                   # prevents collisions between different lines, compiled or not
			cache_key,                                         # allows for custom cache keys
		].freeze

		low_level_cache(full_key, **, &content)

		nil
	end

	# Cache a block of content where you control the entire cache key.
	# If you really know what you’re doing and want to take full control
	# and responsibility for the cache key, use this method.
	#
	# ```ruby
	# low_level_cache([Commonmarker::VERSION, Digest::MD5.hexdigest(@content)]) do
	#   markdown(@content)
	# end
	# ```
	#
	# Note: To allow you more control, this method does not take a splat of cache keys.
	# If you need to pass multiple cache keys, you should pass an array.
	def low_level_cache(cache_key, **options, &content)
		state = @_state

		cached_buffer, fragment_map = cache_store.fetch(cache_key, **options) { state.caching(&content) }

		if state.should_render?
			fragment_map.each do |fragment_name, (offset, length, nested_fragments)|
				state.record_fragment(fragment_name, offset, length, nested_fragments)
			end
			state.buffer << cached_buffer
		else
			found = false
			# Fragments are recorded in document order, and one that isn't nested can still overlap the
			# one before it, so only append the bytes past the end of what's already been selected.
			selected_end = 0

			fragment_map.each do |fragment_name, (offset, length, nested_fragments)|
				if state.fragments.include?(fragment_name)
					found = true
					state.fragments.delete(fragment_name)
					state.fragments.subtract(nested_fragments)

					fragment_end = offset + length
					next if fragment_end <= selected_end

					start = (offset > selected_end) ? offset : selected_end
					state.buffer << cached_buffer.byteslice(start, fragment_end - start)
					selected_end = fragment_end
				end
			end

			state.halt_if_all_fragments_found if found
		end

		nil
	end

	def json_escape(string)
		string.gsub(/[&<>\u2028\u2029]/, {
			"&" => '\u0026',
			"<" => '\u003c',
			">" => '\u003e',
			"\u2028" => '\u2028',
			"\u2029" => '\u2029',
		})
	end

	# Override this method to use a different deployment key.
	private def app_version_key
		Phlex::DEPLOYED_AT
	end

	# Override this method to use a different cache store.
	private def cache_store
		raise "Cache store not implemented."
	end

	private def enable_cache_reloading?
		false
	end

	private def vanish(...)
		capture(...)
		nil
	end

	private def render?
		true
	end

	private def format_object(object)
		case object
		when Float, Integer
			object.to_s
		end
	end

	private def around_template
		yield
		nil
	end

	private def before_template(&)
		nil
	end

	private def after_template(&)
		nil
	end

	# The class or module that registered the element `tag` renders for `name`.
	private def __element_registrar__(name)
		return unless Phlex::SGML::Elements.registered_name?(name)

		self.class.ancestors.find { |ancestor| Phlex::SGML::Elements === ancestor && ancestor.__element_registered__?(name) }
	end

	private def __yield_content__
		return unless block_given?

		state = @_state

		original_length = state.output_bytesize
		content = yield(self)
		__implicit_output__(content) if original_length == state.output_bytesize

		nil
	end

	private def __yield_content_with_no_yield_args__
		return unless block_given?

		state = @_state

		original_length = state.output_bytesize
		content = yield # <-- doesn’t yield self 😉
		__implicit_output__(content) if original_length == state.output_bytesize

		nil
	end

	private def __yield_content_with_args__(*a)
		return unless block_given?

		state = @_state

		original_length = state.output_bytesize
		content = yield(*a)
		__implicit_output__(content) if original_length == state.output_bytesize

		nil
	end

	private def __implicit_output__(content)
		state = @_state
		return true unless state.should_render?

		case content
		when Phlex::SGML::SafeObject
			state.append(content.to_s)
		when String
			state.buffer << Phlex::Escape.html_escape(content)
		when Symbol
			state.buffer << Phlex::Escape.html_escape(content.name)
		when nil
			nil
		else
			if (formatted_object = format_object(content))
				state.buffer << Phlex::Escape.html_escape(formatted_object)
			else
				return false
			end
		end

		true
	end

	# same as __implicit_output__ but escapes even `safe` objects
	private def __text__(content)
		state = @_state
		return true unless state.should_render?

		case content
		when String
			state.buffer << Phlex::Escape.html_escape(content)
		when Symbol
			state.buffer << Phlex::Escape.html_escape(content.name)
		when nil
			nil
		else
			if (formatted_object = format_object(content))
				state.buffer << Phlex::Escape.html_escape(formatted_object)
			else
				return false
			end
		end

		true
	end

	private def __attributes__(attributes)
		@_state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
	end

	private_class_method def self.method_added(method_name)
		if method_name == :view_template
			location = instance_method(method_name).source_location[0]

			if location[0] in "/" | "."
				Phlex.__expand_attribute_cache__(location)
			end
		end

		__inlining_changed__(self, [method_name])
		super
	end

	private_class_method def self.method_removed(method_name)
		__inlining_changed__(self, [method_name])
		super
	end

	private_class_method def self.method_undefined(method_name)
		__inlining_changed__(self, [method_name])
		super
	end

	def self.include(*modules)
		super
		__inlining_changed__(self, modules.flat_map { |mod| mod.instance_methods + mod.private_instance_methods })
		self
	end

	def self.prepend(*modules)
		super
		__inlining_changed__(self, modules.flat_map { |mod| mod.instance_methods + mod.private_instance_methods })
		self
	end

	# A frozen class can't be recompiled when an element or helper it inlined
	# changes, so its original definitions are put back first.
	def self.freeze
		Phlex::Compiler.decompile(self) if !Phlex.__compiled_source_maps__.empty? && Phlex::Compiler.compiled?(self) && !frozen?

		super
	end

	# Compiled methods inline elements and helpers as they were at compile
	# time, so a change to one has to be seen. Nothing to do until something
	# has been compiled.
	private_class_method def self.__inlining_changed__(target, names)
		if names.include?(:__phlex_equal__?) && !Phlex::SGML.equal?(target)
			raise Phlex::NameError, "__phlex_equal__? is reserved for compiled blocks, so it can't be defined on #{target.inspect}."
		end

		Phlex::Compiler.inlining_changed(target, names) unless Phlex.__compiled_source_maps__.empty?
	end

	# Inlined svg blocks rely on the class methods that build a Phlex::SVG.
	# Defined before the hooks below, which call it when it's defined.
	private_class_method def self.__svg_class_changed__(method_name)
		__inlining_changed__(self, [method_name]) if (method_name in :new | :allocate | :===) && Phlex::SVG <= self
	end

	private_class_method def self.singleton_method_added(method_name)
		__svg_class_changed__(method_name)
		super
	end

	private_class_method def self.singleton_method_removed(method_name)
		__svg_class_changed__(method_name)
		super
	end

	private_class_method def self.singleton_method_undefined(method_name)
		__svg_class_changed__(method_name)
		super
	end

	private def singleton_method_added(method_name)
		self.class.__send__(:__inlining_changed__, singleton_class, [method_name])
		super
	end

	def extend(*modules)
		super
		self.class.__send__(:__inlining_changed__, singleton_class, modules.flat_map { |mod| mod.instance_methods + mod.private_instance_methods })
		self
	end

	# BasicObject#equal? under a name a component can't override. A compiled
	# block runs its compiled body only when the component says the block's
	# receiver is itself, rather than asking the receiver, which could be
	# anything.
	define_method(:__phlex_equal__?, BasicObject.instance_method(:equal?))
end
