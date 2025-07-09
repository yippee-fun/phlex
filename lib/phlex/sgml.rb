# frozen_string_literal: true

# **Standard Generalized Markup Language** for behaviour common to {HTML} and {SVG}.
class Phlex::SGML
	ERBCompiler = ERB::Compiler.new("<>").tap do |compiler|
		compiler.pre_cmd    = [""]
		compiler.put_cmd    = "@_state.buffer.<<"
		compiler.insert_cmd = "__implicit_output__"
		compiler.post_cmd   = ["nil"]

		def compiler.add_insert_cmd(out, content)
			out.push("#{@insert_cmd}((#{content}))")
		end
	end

	include Phlex::Helpers

	class << self
		# Render the view to a String. Arguments are delegated to {.new}.
		def call(...)
			new(...).call
		end

		# Create a new instance of the component.
		# @note The block will not be delegated to {#initialize}. Instead, it will be sent to {#view_template} when rendering.
		def new(*a, **k, &block)
			if block
				object = super(*a, **k, &nil)
				object.instance_exec { @_content_block = block }
				object
			else
				super
			end
		end

		def erb(method_name, erb = nil, locals: nil, &block)
			loc = caller_locations(1, 1)[0]
			path = loc.path.delete_suffix(".rb")
			file = loc.path
			line = loc.lineno - 1

			unless erb
				method_path = "#{path}/#{method_name}.html.erb"
				sidecar_path = "#{path}.html.erb"

				if File.exist?(method_path)
					erb = File.read(method_path)
					file = method_path
					line = 1
				elsif method_name == :view_template && File.exist?(sidecar_path)
					erb = File.read(sidecar_path)
					file = sidecar_path
					line = 1
				else
					raise Phlex::RuntimeError.new(<<~MESSAGE)
						No ERB template found for #{method_name}
					MESSAGE
				end
			end

			code, _enc = ERBCompiler.compile(erb)

			class_eval(<<~RUBY, file, line)
				def #{method_name} #{locals}
					#{code}
				end
			RUBY
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

	def call(buffer = +"", context: {}, fragments: nil, &)
		state = Phlex::SGML::State.new(
			user_context: context,
			output_buffer: buffer,
			fragments: fragments&.to_set,
		)

		internal_call(parent: nil, state:, &)

		state.output_buffer << state.buffer
	end

	def internal_call(parent: nil, state: nil, &block)
		if @_state
			raise Phlex::DoubleRenderError.new(
				"You can't render a #{self.class.name} more than once."
			)
		end

		@_state = state

		return "" unless render?

		block ||= @_content_block

		Thread.current[:__phlex_component__] = [self, Fiber.current.object_id].freeze

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
		Thread.current[:__phlex_component__] = [parent, Fiber.current.object_id].freeze
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
	# It will not reset back to false after rendering.
	def rendering?
		!!@_state
	end

	# Output plain text.
	def plain(content)
		unless __text__(content)
			raise Phlex::ArgumentError.new("You've passed an object to plain that is not handled by format_object. See https://rubydoc.info/gems/phlex/Phlex/SGML#format_object-instance_method for more information")
		end

		nil
	end

	# Output a single space character. If a block is given, a space will be output before and after the block.
	def whitespace(&)
		state = @_state
		return unless state.should_render?

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
		return unless state.should_render?

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

			state.buffer << content.to_s
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
		state = @_state
		state.begin_fragment(name)
		yield
		state.end_fragment(name)
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
			location.lineno,                                   # prevents collisions between different lines
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
			fragment_map.each do |fragment_name, (offset, length, nested_fragments)|
				if state.fragments.include?(fragment_name)
					state.fragments.delete(fragment_name)
					state.fragments.subtract(nested_fragments)
					state.buffer << cached_buffer.byteslice(offset, length)
				end
			end
		end

		nil
	end

	def json_escape(string)
		ERB::Util.json_escape(string)
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

	private def before_template
		nil
	end

	private def after_template
		nil
	end

	private def __yield_content__
		return unless block_given?

		buffer = @_state.buffer

		original_length = buffer.bytesize
		content = yield(self)
		__implicit_output__(content) if original_length == buffer.bytesize

		nil
	end

	private def __yield_content_with_no_yield_args__
		return unless block_given?

		buffer = @_state.buffer

		original_length = buffer.bytesize
		content = yield # <-- doesn’t yield self 😉
		__implicit_output__(content) if original_length == buffer.bytesize

		nil
	end

	private def __yield_content_with_args__(*a)
		return unless block_given?

		buffer = @_state.buffer

		original_length = buffer.bytesize
		content = yield(*a)
		__implicit_output__(content) if original_length == buffer.bytesize

		nil
	end

	private def __implicit_output__(content)
		state = @_state
		return true unless state.should_render?

		case content
		when Phlex::SGML::SafeObject
			state.buffer << content.to_s
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

	private def __render_attributes__(attributes)
		state = @_state
		return unless state.should_render?
		state.buffer << (Phlex::ATTRIBUTE_CACHE[attributes] ||= Phlex::SGML::Attributes.generate_attributes(attributes))
	end

	private_class_method def self.method_added(method_name)
		if method_name == :view_template
			location = instance_method(method_name).source_location[0]

			if location[0] in "/" | "."
				Phlex.__expand_attribute_cache__(location)
			end
		end

		super
	end

	def self.__compile__(method_name)
		path, line = instance_method(method_name).source_location
		Phlex::Compiler::Method.new(self, path, line, method_name).compile
	end
end
