# frozen_string_literal: true

class Phlex::SGML::State
	def initialize(user_context: {}, output_buffer:, fragments:)
		@buffer = +""
		@flushed_bytesize = 0
		@capturing = false
		@user_context = user_context
		@fragments = fragments
		@fragment_depth = 0
		@rendering_fragments = nil
		@should_render = !fragments
		@cache_stack = []
		@halt_signal = nil
		@output_buffer = output_buffer
		@attribute_cache = Phlex.__attribute_cache__
	end

	attr_accessor :capturing, :user_context

	attr_reader :fragments, :fragment_depth, :output_buffer, :buffer, :should_render, :attribute_cache

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
		# A selected fragment ends at the first end of its name, so count it once however deeply the name is nested.
		if @fragments&.include?(id) && (@rendering_fragments ||= Set.new).add?(id)
			@fragment_depth += 1
			@should_render = true
		end

		if caching?
			current_byte_offset = 0                                 		# Start tracking the byte offset of this fragment from the start of the cache buffer
			cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)| # We'll iterate deepest to shallowest
				current_byte_offset += cache_buffer.bytesize		      		# Add the length of the cache buffer to the current byte offset
				next if fragment_map.key?(id)                         		# Only the first fragment with a given name can be selected
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
			current_byte_offset = 0
			cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)| # We'll iterate deepest to shallowest
				current_byte_offset += cache_buffer.bytesize
				fragment = fragment_map[id]
				next if fragment[1]                                         # An earlier fragment with this name has already ended
				fragment[1] = current_byte_offset - fragment[0]             # The byte length is the difference between the current byte offset and the byte offset of the fragment
				if (descendants = open_fragments.delete(id))
					# A descendant that's still open ends after this fragment, so it isn't nested in it.
					fragment[2] = descendants.to_a.reject { |name| open_fragments.key?(name) }
				end
			end
		end

		return unless @fragments&.include?(id)

		@fragments.delete(id)
		@fragment_depth -= 1
		@should_render = @fragment_depth > 0
		# Don't replace an exception or nonlocal exit with the render halt signal.
		halt_if_all_fragments_found if halt
	end

	# Appends what a selective render outputs from a cached buffer. That's the union of the selected
	# fragments in it, plus everything up to where each open selected fragment ends, since a selected
	# fragment ends at the first end of its name. An open one that doesn't end in it covers all of it.
	def select_from_cache(cached_buffer, fragment_map)
		fragments = @fragments
		ranges = []
		found = false

		fragment_map.each do |id, (offset, length, nested_fragments)|
			next unless fragments.include?(id)

			found = true
			fragments.delete(id)

			if @rendering_fragments&.include?(id)
				@fragment_depth -= 1
				ranges << [0, offset + length]
			else
				fragments.subtract(nested_fragments)
				ranges << [offset, offset + length]
			end
		end

		ranges << [0, cached_buffer.bytesize] if @fragment_depth > 0
		@should_render = @fragment_depth > 0

		selected_end = 0
		ranges.sort_by!(&:first).each do |(range_start, range_end)|
			next if range_end <= selected_end

			range_start = selected_end if range_start < selected_end
			@buffer << cached_buffer.byteslice(range_start, range_end - range_start)
			selected_end = range_end
		end

		halt_if_all_fragments_found if found
	end

	def halt_if_all_fragments_found
		throw @halt_signal if @fragments.length == 0
	end

	def record_fragment(id, offset, length, nested_fragments)
		return unless caching?

		cache_stack.reverse_each do |(cache_buffer, fragment_map, open_fragments)|
			offset += cache_buffer.bytesize

			if (fragment = fragment_map[id])
				# An open fragment with this name ends where the recorded one does.
				unless fragment[1]
					fragment[1] = offset + length - fragment[0]
					descendants = open_fragments.delete(id)
					# A descendant that's still open ends after this fragment, so it isn't nested in it.
					fragment[2] = descendants ? descendants.to_a.reject { |name| open_fragments.key?(name) } | nested_fragments : nested_fragments
				end

				next
			end

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
		!(cache_stack = @cache_stack) || cache_stack.length > 0
	end

	# A capture has no cache stack until it needs to track a fragment.
	# While it has none, `buffer` is the buffer being captured into.
	private def cache_stack
		@cache_stack ||= [[buffer, {}, {}]]
	end

	def capture(cache: false)
		new_buffer = +""
		original_buffer = @buffer
		original_capturing = @capturing
		original_fragments = @fragments
		original_should_render = @should_render
		original_cache_stack = cache ? cache_stack : @cache_stack
		captured_cache_stack = nil

		begin
			@buffer = new_buffer
			@capturing = true
			@fragments = nil
			@should_render = true
			# Captured output may be inserted later, elsewhere, or not at all.
			# Track its fragments locally until the original string is inserted.
			@cache_stack = nil unless cache
			yield
		ensure
			captured_cache_stack = @cache_stack unless cache
			@buffer = original_buffer
			@capturing = original_capturing
			@fragments = original_fragments
			@should_render = original_should_render
			@cache_stack = original_cache_stack
		end

		if captured_cache_stack && !(fragment_map = captured_cache_stack[0][1]).empty?
			# Let the string own its metadata so discarded captures can be collected
			# without losing metadata for strings that will be inserted again.
			new_buffer.instance_variable_set(:@__phlex_fragments, [new_buffer.dup.freeze, fragment_map])
		end

		new_buffer
	end

	# Flushing moves bytes out of the buffer without changing how much was written.
	# Read through `buffer` so overrides that redirect output (e.g. phlex-rails) are measured too.
	def output_bytesize
		@flushed_bytesize + buffer.bytesize
	end

	def append(content)
		# Changed strings no longer have reliable fragment offsets.
		if caching? && (captured = content.instance_variable_get(:@__phlex_fragments)) && captured[0] == content
			captured[1].each do |id, (offset, length, nested_fragments)|
				record_fragment(id, offset, length, nested_fragments)
			end
		end

		buffer << content
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
