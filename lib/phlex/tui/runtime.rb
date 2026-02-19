# frozen_string_literal: true

class Phlex::TUI::Runtime
	class Event
		def initialize(type:, target:, target_owner:, target_name:, timestamp:, payload:)
			@data = {
				type:,
				target:,
				target_owner:,
				target_name:,
				timestamp:,
				**payload,
			}
			@propagation_stopped = false
			@default_prevented = false
			@dispatched = false
		end

		def [](key)
			@data[key]
		end

		def []=(key, value)
			@data[key] = value
		end

		def stop_propagation!
			@propagation_stopped = true
			nil
		end

		def propagation_stopped?
			@propagation_stopped
		end

		def prevent_default!
			@default_prevented = true
			nil
		end

		def default_prevented?
			@default_prevented
		end

		def dispatched?
			@dispatched
		end

		def set_current_target!(id:, owner:, name:)
			@data[:current_target] = id
			@data[:current_owner] = owner
			@data[:current_name] = name
			@data[:owner] = owner
			@data[:name] = name
			nil
		end

		def mark_dispatched!
			@dispatched = true
			nil
		end
	end

	def initialize
		@events = {}
		@event_ids_by_scope = {}
		@event_id_by_node_object_id = {}
		@hit_cells_by_scope = {}
		@focusables_by_scope = {}
		@previous_focusables_by_scope = {}
		@dialog_scopes = []
		@dialog_order = 0
		@active_scope = :root
		@focused_id = nil
	end

	attr_reader :active_scope
	attr_reader :focused_id

	def begin_frame!
		@events = {}
		@event_ids_by_scope = {}
		@event_id_by_node_object_id = {}
		@hit_cells_by_scope = {}
		@focusables_by_scope = {}
		@dialog_scopes = []
		@dialog_order = 0
	end

	def finalize_frame!
		rebuild_hit_cells!
		@active_scope = resolve_active_scope
		focusables = focusables_for_active_scope

		if focusables.empty?
			@focused_id = nil
			@previous_focusables_by_scope = snapshot_focusables
			return
		end

		if @focused_id && !focusables.include?(@focused_id)
			@focused_id = fallback_focus_id
		end

		@previous_focusables_by_scope = snapshot_focusables
	end

	def register_element(id:, owner:, handlers: {}, focusable: false, scope: :root)
		if @events.key?(id)
			raise ArgumentError, "duplicate element name for component: #{id.inspect}"
		end

		@events[id] = {
			owner:,
			handlers: handlers.dup,
			scope:,
			node: nil,
		}

		(@event_ids_by_scope[scope] ||= []) << id

		if focusable
			focusables = (@focusables_by_scope[scope] ||= [])
			if focusables.include?(id)
				raise ArgumentError, "duplicate focus name for component: #{id.inspect}"
			end

			focusables << id
		end

		id
	end

	def update_element_node(id, node)
		entry = @events[id]
		return unless entry

		scope = entry[:scope]
		node_ids = (@event_id_by_node_object_id[scope] ||= {}.compare_by_identity)
		previous_node = entry[:node]
		node_ids.delete(previous_node) if previous_node
		entry[:node] = node
		node_ids[node] = id if node
	end

	def register_dialog_scope(scope:, z:)
		@dialog_scopes << { scope:, z:, order: @dialog_order }
		@dialog_order += 1
		scope
	end

	def event_for(id)
		@events[id]
	end

	def dispatch(id, type:, **payload)
		entry = @events[id]
		return false unless entry

		handler = entry[:handlers][type]
		return false unless handler

		event = build_event(type:, target_id: id, entry:, payload:)
		event.set_current_target!(id:, owner: entry[:owner], name: extract_name(id))

		invoke_handler(entry[:owner], handler, event)
		true
	end

	def dispatch_bubbled(id, type:, scope: @active_scope, **payload)
		entry = @events[id]
		return nil unless entry
		return nil unless entry[:scope] == scope

		event = build_event(type:, target_id: id, entry:, payload:)
		path = event_path_for(id, scope:)

		path.each do |current_id|
			current_entry = @events[current_id]
			next unless current_entry
			next unless current_entry[:scope] == scope

			handler = current_entry[:handlers][type]
			next unless handler

			event.set_current_target!(id: current_id, owner: current_entry[:owner], name: extract_name(current_id))
			invoke_handler(current_entry[:owner], handler, event)
			event.mark_dispatched!
			break if event.propagation_stopped?
		end

		event
	end

	def event_path_for(id, scope: @active_scope)
		entry = @events[id]
		return [] unless entry
		return [] unless entry[:scope] == scope

		path = [id]
		seen = { id => true }
		node = entry[:node]
		node = node.parent if node.respond_to?(:parent)

		while node
			current_id = event_id_for_node(node, scope)
			if current_id && !seen[current_id]
				path << current_id
				seen[current_id] = true
			end

			node = node.respond_to?(:parent) ? node.parent : nil
		end

		path
	end

	def hit_test(col:, row:, scope: @active_scope)
		hit_cells = @hit_cells_by_scope[scope]
		return nil unless hit_cells

		hit_cells[[col, row]]
	end

	def focused?(id)
		@focused_id == id
	end

	def focus_next!
		focusables = focusables_for_active_scope
		return false if focusables.empty?

		current_index = focusables.index(@focused_id)
		next_index = current_index ? ((current_index + 1) % focusables.length) : 0
		next_focus = focusables[next_index]

		changed = @focused_id != next_focus
		@focused_id = next_focus
		changed
	end

	def focus_previous!
		focusables = focusables_for_active_scope
		return false if focusables.empty?

		current_index = focusables.index(@focused_id)
		previous_index = current_index ? ((current_index - 1) % focusables.length) : (focusables.length - 1)
		previous_focus = focusables[previous_index]

		changed = @focused_id != previous_focus
		@focused_id = previous_focus
		changed
	end

	def focus!(id)
		entry = @events[id]
		return false unless entry
		return false unless entry[:scope] == @active_scope

		changed = @focused_id != id
		@focused_id = id
		changed
	end

	private def resolve_active_scope
		dialog = @dialog_scopes.max_by { |entry| [entry[:z], entry[:order]] }
		dialog ? dialog[:scope] : :root
	end

	private def focusables_for_active_scope
		@focusables_by_scope[@active_scope] || []
	end

	private def snapshot_focusables
		@focusables_by_scope.transform_values(&:dup)
	end

	private def fallback_focus_id
		focusables = focusables_for_active_scope
		previous_focusables = @previous_focusables_by_scope[@active_scope] || []

		if !previous_focusables.empty?
			index = previous_focusables.index(@focused_id)
			if index
				return focusables[index] if index < focusables.length
				return focusables[index - 1] if index.positive?
			end
		end

		focusables.first
	end

	private def extract_name(id)
		return id[1] if Array === id && id.length > 1

		id
	end

	private def invoke_handler(owner, handler, event)
		case handler
		in Proc
			owner.instance_exec(event, &handler)
		in Symbol => method_name
			owner.__send__(method_name, event)
		else
			raise ArgumentError, "Unsupported event handler: #{handler.inspect}"
		end
	end

	private def build_event(type:, target_id:, entry:, payload:)
		Event.new(
			type:,
			target: target_id,
			target_owner: entry[:owner],
			target_name: extract_name(target_id),
			timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second),
			payload:
		)
	end

	private def event_id_for_node(node, scope)
		node_ids = @event_id_by_node_object_id[scope]
		if node_ids
			id = node_ids[node]
			return id if id
		end

		ids = @event_ids_by_scope[scope]
		return nil unless ids

		ids.each do |id|
			entry = @events[id]
			next unless entry
			return id if entry[:node].equal?(node)
		end

		nil
	end

	private def rebuild_hit_cells!
		@hit_cells_by_scope = {}

		@event_ids_by_scope.each do |scope, ids|
			ids.each do |id|
				entry = @events[id]
				node = entry && entry[:node]
				next unless node

				paint_hit_cells(id, scope, node)
			end
		end
	end

	private def paint_hit_cells(id, scope, node)
		return unless Integer === node.row && Integer === node.col
		return unless Integer === node.width && Integer === node.height
		return if node.respond_to?(:pointer_events) && node.pointer_events == :none

		hit_cells = (@hit_cells_by_scope[scope] ||= {})
		row_start = node.row
		row_stop = node.row + node.height
		col_start = node.col
		col_stop = node.col + node.width

		row = row_start
		while row < row_stop
			col = col_start
			while col < col_stop
				hit_cells[[col, row]] = id
				col += 1
			end

			row += 1
		end
	end
end
