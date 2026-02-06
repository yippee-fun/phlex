# frozen_string_literal: true

module Phlex
	# **Standard Generalized Markup Language** for behaviour common to {HTML} and {SVG}.
	class SGML
		include Helpers
		REF_ATTRIBUTES = Set.new(%w[href src action formaction lowsrc dynsrc background ping xlinkhref]).freeze
		NAMED_CHARACTER_REFERENCES = {
			"colon" => ":",
			"tab" => "\t",
			"newline" => "\n",
		}.freeze
		UNSAFE_ATTRIBUTE_NAME_CHARS = %r([<>&"'/=\s\x00])

		class << self
			# Render the view to a String. Arguments are delegated to {.new}.
			def call(...)
				new(...).call
			end

			# Create a new instance of the component.
			# @note The block will not be delegated {#initialize}. Instead, it will be sent to {#template} when rendering.
			def new(*args, **kwargs, &block)
				if block
					object = super(*args, **kwargs, &nil)
					object.instance_variable_set(:@_content_block, block)
					object
				else
					super
				end
			end

			# @api private
			def rendered_at_least_once!
				alias_method :__attributes__, :__final_attributes__
				alias_method :call, :__final_call__
			end

			# @api private
			def element_method?(method_name)
				return false unless instance_methods.include?(method_name)

				owner = instance_method(method_name).owner

				return true if owner.is_a?(Phlex::Elements) && owner.registered_elements[method_name]

				false
			end
		end

		# @!method initialize
		# @abstract Override to define an initializer for your component.
		# @note Your initializer will not receive a block passed to {.new}. Instead, this block will be sent to {#template} when rendering.
		# @example
		# 	def initialize(articles:)
		# 		@articles = articles
		# 	end

		# @abstract Override to define a template for your component.
		# @example
		# 	def view_template
		# 		h1 { "👋 Hello World!" }
		# 	end
		# @example Your template may yield a content block.
		# 	def view_template
		# 		main {
		# 			h1 { "Hello World" }
		# 			yield
		# 		}
		# 	end
		# @example Alternatively, you can delegate the content block to an element.
		# 	def view_template(&block)
		# 		article(class: "card", &block)
		# 	end
		def template
			yield
		end

		def self.method_added(method_name)
			if method_name == :template
				Kernel.warn "⚠️ [DEPRECATION] Defining the `template` method on a Phlex component will not be supported in Phlex 2.0. Please rename `#{name}#template` to `#{name}#view_template` instead."
			end
		end

		def view_template(&block)
			template(&block)
		end

		def await(task)
			case task
			when defined?(Concurrent::IVar) && Concurrent::IVar
				flush if task.pending?
				task.wait.value
			when defined?(Async::Task) && Async::Task
				flush if task.running?
				task.wait
			else
				raise ArgumentError, "Expected an asynchronous task / promise."
			end
		end

		# Renders the view and returns the buffer. The default buffer is a mutable String.
		def call(...)
			__final_call__(...).tap do
				self.class.rendered_at_least_once!
			end
		end

		# @api private
		def __final_call__(buffer = +"", context: Phlex::Context.new, view_context: nil, parent: nil, fragments: nil, &block)
			@_buffer = buffer
			@_context = context
			@_view_context = view_context
			@_parent = parent
			if @_rendered
			  warn "⚠️ [WARNING] You are rendering a component #{self.class.name} twice. This is not supported in Phlex 2.0."
			end
	    @_rendered = true

			if fragments
				warn "⚠️ [WARNING] Selective Rendering is experimental, incomplete, and may change in future versions."
				@_context.target_fragments(fragments)
			end

			block ||= @_content_block

			return "" unless render?

			if !parent && Phlex::SUPPORTS_FIBER_STORAGE
				original_fiber_storage = Fiber[:__phlex_component__]
				Fiber[:__phlex_component__] = self
			end

			@_context.around_render do
				around_template do
					if block
						if is_a?(DeferredRender)
							__vanish__(self, &block)
							view_template
						else
							view_template do |*args|
								if args.length > 0
									yield_content_with_args(*args, &block)
								else
									yield_content(&block)
								end
							end
						end
					else
						view_template
					end
				end
			end

			unless parent
				if Phlex::SUPPORTS_FIBER_STORAGE
					Fiber[:__phlex_component__] = original_fiber_storage
				end
				buffer << context.buffer
			end
		end

		# Access the current render context data
		# @return the supplied context object, by default a Hash
		def context
			@_context.user_context
		end

		# Output text content. The text will be HTML-escaped.
		# @param content [String, Symbol, Integer, void] the content to be output on the buffer. Strings, Symbols, and Integers are handled by `plain` directly, but any object can be handled by overriding `format_object`
		# @return [nil]
		# @see #format_object
		def plain(content)
			unless __text__(content)
				raise ArgumentError, "You've passed an object to plain that is not handled by format_object. See https://rubydoc.info/gems/phlex/Phlex/SGML#format_object-instance_method for more information"
			end

			nil
		end

		# Output a whitespace character. This is useful for getting inline elements to wrap. If you pass a block, a whitespace will be output before and after yielding the block.
		# @return [nil]
		# @yield If a block is given, it yields the block with no arguments.
		def whitespace(&block)
			context = @_context
			return if context.fragments && !context.in_target_fragment

			buffer = context.buffer

			buffer << " "

			if block_given?
				yield_content(&block)
				buffer << " "
			end

			nil
		end

		# Output an HTML comment.
		# @return [nil]
		def comment(&block)
			context = @_context
			return if context.fragments && !context.in_target_fragment

			buffer = context.buffer

			buffer << "<!-- "
			yield_content(&block)
			buffer << " -->"

			nil
		end

		# This method is very dangerous and should usually be avoided. It will output the given String without any HTML safety. You should never use this method to output unsafe user input.
		# @param content [String|nil]
		# @return [nil]
		def unsafe_raw(content = nil)
			return nil unless content

			context = @_context
			return if context.fragments && !context.in_target_fragment

			context.buffer << content
			nil
		end

		# Capture a block of output as a String.
		# @note This only works if the block's receiver is the current component or the block returns a String.
		# @return [String]
		def capture(*args, &block)
			return "" unless block

			if args.length > 0
				@_context.capturing_into(+"") { yield_content_with_args(*args, &block) }
			else
				@_context.capturing_into(+"") { yield_content(&block) }
			end
		end

		private

		# @api private
		def flush
			return if @_context.capturing

			buffer = @_context.buffer
			@_buffer << buffer.dup
			buffer.clear
		end

		# Render another component, block or enumerable
		# @return [nil]
		# @overload render(component, &block)
		# 	Renders the component.
		# 	@param component [Phlex::SGML]
		# @overload render(component_class, &block)
		# 	Renders a new instance of the component class. This is useful for component classes that take no arguments.
		# 	@param component_class [Class<Phlex::SGML>]
		# @overload render(proc)
		# 	Renders the proc with {#yield_content}.
		# 	@param proc [Proc]
		# @overload render(enumerable)
		# 	Renders each item of the enumerable.
		# 	@param enumerable [Enumerable]
		# 	@example
		# 		render @items
		def render(renderable, &block)
			case renderable
			when Phlex::SGML
				renderable.call(@_buffer, context: @_context, view_context: @_view_context, parent: self, &block)
			when Class
				if renderable < Phlex::SGML
					renderable.new.call(@_buffer, context: @_context, view_context: @_view_context, parent: self, &block)
				end
			when Enumerable
				renderable.each { |r| render(r, &block) }
			when Proc, Method
				if renderable.arity == 0
					yield_content_with_no_args(&renderable)
				else
					yield_content(&renderable)
				end
			when String
				plain(renderable)
			else
				raise ArgumentError, "You can't render a #{renderable.inspect}."
			end

			nil
		end

		# Like {#capture} but the output is vanished into a BlackHole buffer.
		# Because the BlackHole does nothing with the output, this should be faster.
		# @return [nil]
		# @api private
		def __vanish__(*args)
			return unless block_given?

			@_context.capturing_into(BlackHole) { yield(*args) }

			nil
		end

		# Determines if the component should render. By default, it returns `true`.
		# @abstract Override to define your own predicate to prevent rendering.
		# @return [Boolean]
		def render?
			true
		end

		# Format the object for output
		# @abstract Override to define your own format handling for different object types. Please remember to call `super` in the case that the passed object doesn't match, so that object formatting can be added at different layers of the inheritance tree.
		# @return [String]
		def format_object(object)
			case object
			when Float, Integer
				object.to_s
			end
		end

		# @abstract Override this method to hook in around a template render. You can do things before and after calling `super` to render the template. You should always call `super` so that callbacks can be added at different layers of the inheritance tree.
		# @return [nil]
		def around_template
			before_template
			yield
			after_template

			nil
		end

		# @abstract Override this method to hook in right before a template is rendered. Please remember to call `super` so that callbacks can be added at different layers of the inheritance tree.
		# @return [nil]
		def before_template
			nil
		end

		# @abstract Override this method to hook in right after a template is rendered. Please remember to call `super` so that callbacks can be added at different layers of the inheritance tree.
		# @return [nil]
		def after_template
			nil
		end

		# Yields the block and checks if it buffered anything. If nothing was buffered, the return value is treated as text. The text is always HTML-escaped.
		# @yieldparam component [self]
		# @return [nil]
		def yield_content
			return unless block_given?

			buffer = @_context.buffer

			original_length = buffer.bytesize
			content = yield(self)
			__text__(content) if original_length == buffer.bytesize

			nil
		end

		# Same as {#yield_content} but yields no arguments.
		# @yield Yields the block with no arguments.
		def yield_content_with_no_args
			return unless block_given?

			buffer = @_context.buffer

			original_length = buffer.bytesize
			content = yield
			__text__(content) if original_length == buffer.bytesize

			nil
		end

		# Same as {#yield_content} but accepts a splat of arguments to yield. This is slightly slower than {#yield_content}.
		# @yield [*args] Yields the given arguments.
		# @return [nil]
		def yield_content_with_args(*args)
			return unless block_given?

			buffer = @_context.buffer

			original_length = buffer.bytesize
			content = yield(*args)
			__text__(content) if original_length == buffer.bytesize

			nil
		end

		# Performs the same task as the public method #plain, but does not raise an error if an unformattable object is passed
		# @api private
		def __text__(content)
			context = @_context
			return true if context.fragments && !context.in_target_fragment

			case content
			when String
				@_context.buffer << Phlex::Escape.html_escape(content)
			when Symbol
				@_context.buffer << Phlex::Escape.html_escape(content.name)
			when nil
				nil
			else
				if (formatted_object = format_object(content))
					@_context.buffer << Phlex::Escape.html_escape(formatted_object)
				else
					return false
				end
			end

			true
		end

		# @api private
		def __attributes__(**attributes)
			__final_attributes__(**attributes).tap do |buffer|
				Phlex::ATTRIBUTE_CACHE[respond_to?(:process_attributes) ? (attributes.hash + self.class.hash) : attributes.hash] = buffer.freeze
			end
		end

		# @api private
		def __final_attributes__(**attributes)
			if respond_to?(:process_attributes)
				attributes = process_attributes(**attributes)
			end

			buffer = +""
			__build_attributes__(attributes, buffer: buffer)

			buffer
		end

		def decode_html_character_references(value)
			value
				.gsub(/&#x([0-9a-f]+);?/i) {
					begin
						[$1.to_i(16)].pack("U*")
					rescue
						""
					end
				}
				.gsub(/&#(\d+);?/) {
					begin
						[$1.to_i].pack("U*")
					rescue
						""
					end
				}
				.gsub(/&([a-z][a-z0-9]+);?/i) {
					NAMED_CHARACTER_REFERENCES[$1.downcase] || ""
				}
		end

		# @api private
		def __build_attributes__(attributes, buffer:)
			attributes.each do |k, v|
				next unless v

				name = case k
					when String then k
					when Symbol then k.name.tr("_", "-")
					else raise ArgumentError, "Attribute keys should be Strings or Symbols."
				end

				lower_name = name.downcase
				normalized_name = lower_name.delete("^a-z")

				if REF_ATTRIBUTES.include?(normalized_name)
					decoded_value = case v
						when String then decode_html_character_references(v)
						when Symbol then decode_html_character_references(v.name)
					end

					if decoded_value && decoded_value.downcase.tr("^a-z:", "").start_with?("javascript:")
						next
					end
				end

				# Detect unsafe attribute names. Attribute names are considered unsafe if they match an event attribute or include unsafe characters.
				if HTML::EVENT_ATTRIBUTES.include?(lower_name.tr("^a-z-", "")) || name.match?(UNSAFE_ATTRIBUTE_NAME_CHARS)
					raise ArgumentError, "Unsafe attribute name detected: #{k}."
				end

				if lower_name.to_sym == :id && k != :id
				  warn "⚠️ [WARNING] Starting 2.0 Phlex will raise on non lowercase or string :id attribute."
				end

				case v
				when true
					buffer << " " << name
				when String
					buffer << " " << name << '="' << Phlex::Escape.html_escape(v) << '"'
				when Symbol
					buffer << " " << name << '="' << Phlex::Escape.html_escape(v.name) << '"'
				when Integer, Float
					buffer << " " << name << '="' << v.to_s << '"'
				when Hash
					__build_attributes__(
						v.transform_keys { |subkey|
							case subkey
								when Symbol then"#{name}-#{subkey.name.tr('_', '-')}"
								else "#{name}-#{subkey}"
							end
						}, buffer: buffer
					)
				when Array
					buffer << " " << name << '="' << Phlex::Escape.html_escape(v.compact.join(" ")) << '"'
				when Set
					buffer << " " << name << '="' << Phlex::Escape.html_escape(v.to_a.compact.join(" ")) << '"'
				else
					value = if v.respond_to?(:to_phlex_attribute_value)
						v.to_phlex_attribute_value
					elsif v.respond_to?(:to_str)
						v.to_str
					else
						v.to_s
					end

					buffer << " " << name << '="' << Phlex::Escape.html_escape(value) << '"'
				end
			end

			buffer
		end
	end
end
