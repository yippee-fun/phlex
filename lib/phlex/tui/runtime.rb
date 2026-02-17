# frozen_string_literal: true

class Phlex::TUI::Runtime
	def initialize
		@events = {}
		@focusables = []
		@previous_focusables = []
		@focused_id = nil
	end

	attr_reader :focused_id

	def begin_frame!
		@events = {}
		@focusables = []
	end

	def finalize_frame!
		if @focusables.empty?
			@focused_id = nil
			@previous_focusables = @focusables.dup
			return
		end

		if @focused_id && !@focusables.include?(@focused_id)
			@focused_id = fallback_focus_id
		end

		@previous_focusables = @focusables.dup
	end

	def register_element(id:, owner:, handlers: {}, focusable: false)
		@events[id] = {
			owner:,
			handlers: handlers.dup,
		}

		@focusables << id if focusable
		id
	end

	def event_for(id)
		@events[id]
	end

	def focused?(id)
		@focused_id == id
	end

	def focus_next!
		return false if @focusables.empty?

		current_index = @focusables.index(@focused_id)
		next_index = current_index ? ((current_index + 1) % @focusables.length) : 0
		next_focus = @focusables[next_index]

		changed = @focused_id != next_focus
		@focused_id = next_focus
		changed
	end

	def focus_previous!
		return false if @focusables.empty?

		current_index = @focusables.index(@focused_id)
		previous_index = current_index ? ((current_index - 1) % @focusables.length) : (@focusables.length - 1)
		previous_focus = @focusables[previous_index]

		changed = @focused_id != previous_focus
		@focused_id = previous_focus
		changed
	end

	private def fallback_focus_id
		if !@previous_focusables.empty?
			index = @previous_focusables.index(@focused_id)
			if index
				return @focusables[index] if index < @focusables.length
				return @focusables[index - 1] if index.positive?
			end
		end

		@focusables.first
	end
end
