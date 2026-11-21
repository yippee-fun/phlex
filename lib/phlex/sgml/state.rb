# frozen_string_literal: true

class Phlex::SGML::State
	def initialize(user_context: {}, output_buffer:, fragments:)
		@buffer = +""
		@capturing = false
		@user_context = user_context
		@fragments = fragments
		@fragment_depth = 0
		@cache_stack = []
		@halt_signal = nil
		@output_buffer = output_buffer
	end

	attr_accessor :capturing, :user_context

	attr_reader :fragments, :fragment_depth, :output_buffer, :buffer

	def around_render(component)
		stack = @stack

		if !@fragments || @halt_signal
			yield
		else
			catch do |signal|
				@halt_signal = signal
				yield
			end
		end
	end

	def should_render?
		!@fragments || @fragment_depth > 0
	end

	def begin_fragment(id)
		@fragment_depth += 1 if @fragments&.include?(id)

		if caching?
			current_byte_offset = 0                                 		# Start tracking the byte offset of this fragment from the start of the cache buffer
			@cache_stack.reverse_each do |(cache_buffer, fragment_map)| # We'll iterate deepest to shallowest
				current_byte_offset += cache_buffer.bytesize		      		# Add the length of the cache buffer to the current byte offset
				next if fragment_map.key?(id)                         		# Only the first fragment with a given name can be selected
				fragment_map[id] = [current_byte_offset, nil, []]     		# Record the byte offset, length, and store a list of the nested fragments

				fragment_map.each do |name, (_offset, length, nested_fragments)| # Iterate over the other fragments
					next if name == id || length                       						 # Skip if it's the current fragment, or if the fragment has already ended
					nested_fragments << id                                       	 # Add the current fragment to the list of nested fragments
				end
			end
		end
	end

	def end_fragment(id)
		if caching?
			current_byte_offset = 0
			@cache_stack.reverse_each do |(cache_buffer, fragment_map)|   # We'll iterate deepest to shallowest
				current_byte_offset += cache_buffer.bytesize
				fragment = fragment_map[id]
				next if fragment[1]                                         # An earlier fragment with this name has already ended
				fragment[1] = current_byte_offset - fragment[0]             # The byte length is the difference between the current byte offset and the byte offset of the fragment
			end
		end

		return unless @fragments&.include?(id)

		@fragments.delete(id)
		@fragment_depth -= 1
		halt_if_all_fragments_found
	end

	def halt_if_all_fragments_found
		throw @halt_signal if @fragments.length == 0
	end

	def record_fragment(id, offset, length, nested_fragments)
		return unless caching?

		@cache_stack.reverse_each do |(cache_buffer, fragment_map)|
			offset += cache_buffer.bytesize

			if (fragment = fragment_map[id])
				# An open fragment with this name ends where the recorded one does.
				fragment[1] ||= offset + length - fragment[0]
			else
				fragment_map[id] = [offset, length, nested_fragments]
			end
		end
	end

	# Captured output isn't written to the cache buffer, so its fragments have no offsets in it.
	def suspend_caching
		original_cache_stack = @cache_stack
		@cache_stack = []
		yield
	ensure
		@cache_stack = original_cache_stack
	end

	def caching(&)
		result = nil

		capture do
			@cache_stack.push([buffer, {}].freeze)
			yield
			result = @cache_stack.pop
		end

		result
	end

	def caching?
		@cache_stack.length > 0
	end

	def capture
		new_buffer = +""
		original_buffer = @buffer
		original_capturing = @capturing
		original_fragments = @fragments

		begin
			@buffer = new_buffer
			@capturing = true
			@fragments = nil
			yield
		ensure
			@buffer = original_buffer
			@capturing = original_capturing
			@fragments = original_fragments
		end

		new_buffer
	end

	def flush
		return if capturing

		buffer = @buffer
		@output_buffer << buffer.dup

		buffer.clear
		nil
	end
end
