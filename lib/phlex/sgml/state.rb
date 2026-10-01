# frozen_string_literal: true

class Phlex::SGML::State
	def initialize(user_context: {}, output_buffer:, fragments:)
		@buffer = +""
		@flushed_bytesize = 0
		@capturing = false
		@user_context = user_context
		@fragments = fragments
		@fragment_depth = 0
		@should_render = !fragments
		@cache_stack = []
		@halt_signal = nil
		@output_buffer = output_buffer
	end

	attr_accessor :capturing, :user_context

	attr_reader :fragments, :fragment_depth, :output_buffer, :buffer, :should_render

	# Kept as a stored boolean so the check is a plain attribute read.
	alias_method :should_render?, :should_render

	def around_render(component)
		if !@fragments || @halt_signal
			yield
		else
			catch do |signal|
				@halt_signal = signal
				yield
			end
		end
	end

	def begin_fragment(id)
		if @fragments&.include?(id)
			@fragment_depth += 1
			@should_render = true
		end

		if caching?
			current_byte_offset = 0                                 		# Start tracking the byte offset of this fragment from the start of the cache buffer
			@cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)| # We'll iterate deepest to shallowest
				current_byte_offset += cache_buffer.bytesize		      		# Add the length of the cache buffer to the current byte offset
				fragment_map[id] = [current_byte_offset, nil, []]     		# Record the byte offset, length, and store a list of the nested fragments

				# Visit only open ancestors; allocate descendant sets on their first child.
				open_fragments.delete(id)
				open_fragments.each_key { |name| (open_fragments[name] ||= Set.new) << id }
				open_fragments[id] = nil
			end
		end
	end

	def end_fragment(id, halt: true)
		if caching?
			byte_length = nil
			@cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)| # We'll iterate deepest to shallowest
				byte_length ||= cache_buffer.bytesize - fragment_map[id][0] # The byte length is the difference between the current byte offset and the byte offset of the fragment
				fragment_map[id][1] = byte_length                           # All cache contexts use the same byte length
				if (descendants = open_fragments.delete(id))
					fragment_map[id][2] = descendants.to_a
				end
			end
		end

		return unless @fragments&.include?(id)

		@fragments.delete(id)
		@fragment_depth -= 1
		@should_render = @fragment_depth > 0
		# Don't replace an exception or nonlocal exit with the render halt signal.
		throw @halt_signal if halt && @fragments.length == 0
	end

	def record_fragment(id, offset, length, nested_fragments)
		return unless caching?

		@cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)|
			offset += cache_buffer.bytesize
			fragment_map[id] = [offset, length, nested_fragments]

			open_fragments.delete(id)
			open_fragments.each_key { |name| (open_fragments[name] ||= Set.new) << id }
		end
	end

	def caching(&)
		result = nil

		capture(cache: true) do
			@cache_stack.push([buffer, {}, {}].freeze)
			begin
				yield
				result = @cache_stack.last.first(2)
			ensure
				@cache_stack.pop
			end
		end

		result
	end

	def caching?
		@cache_stack.length > 0
	end

	def capture(cache: false)
		new_buffer = +""
		original_buffer = @buffer
		original_capturing = @capturing
		original_fragments = @fragments
		original_should_render = @should_render
		original_cache_stack = @cache_stack
		fragment_map = {} unless cache

		begin
			@buffer = new_buffer
			@capturing = true
			@fragments = nil
			@should_render = true
			# Captured output may be inserted later, elsewhere, or not at all.
			# Track its fragments locally until the original string is inserted.
			@cache_stack = [[new_buffer, fragment_map, {}]] unless cache
			yield
		ensure
			@buffer = original_buffer
			@capturing = original_capturing
			@fragments = original_fragments
			@should_render = original_should_render
			@cache_stack = original_cache_stack
		end

		if fragment_map && !fragment_map.empty?
			# Let the string own its metadata so discarded captures can be collected
			# without losing metadata for strings that will be inserted again.
			new_buffer.instance_variable_set(:@__phlex_fragments, [new_buffer.dup.freeze, fragment_map])
		end

		new_buffer
	end

	# Flushing moves bytes out of the buffer without changing how much was written.
	def output_bytesize
		@flushed_bytesize + @buffer.bytesize
	end

	def append(content)
		# Changed strings no longer have reliable fragment offsets.
		if caching? && (captured = content.instance_variable_get(:@__phlex_fragments)) && captured[0] == content
			captured[1].each do |id, (offset, length, nested_fragments)|
				record_fragment(id, offset, length, nested_fragments)
			end
		end

		@buffer << content
	end

	def flush
		return if capturing

		buffer = @buffer
		@output_buffer << buffer.dup

		@flushed_bytesize += buffer.bytesize
		buffer.clear
		nil
	end
end
