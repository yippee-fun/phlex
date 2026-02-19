# frozen_string_literal: true

class Phlex::TUI::Event
	def initialize(timestamp: nil)
		@timestamp = timestamp || Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
		@target = nil
		@target_owner = nil
		@target_name = nil
		@current_target = nil
		@current_owner = nil
		@current_name = nil
		@propagation_stopped = false
		@default_prevented = false
		@dispatched = false
	end

	attr_reader :timestamp
	attr_reader :target
	attr_reader :target_owner
	attr_reader :target_name
	attr_reader :current_target
	attr_reader :current_owner
	attr_reader :current_name

	def name
		@current_name
	end

	def owner
		@current_owner
	end

	def set_target!(id:, owner:, name:)
		@target = id
		@target_owner = owner
		@target_name = name
		set_current_target!(id:, owner:, name:)
		nil
	end

	def set_current_target!(id:, owner:, name:)
		@current_target = id
		@current_owner = owner
		@current_name = name
		nil
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

	def mark_dispatched!
		@dispatched = true
		nil
	end
end
