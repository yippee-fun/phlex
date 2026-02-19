# frozen_string_literal: true

class Phlex::TUI::KeyDownEvent < Phlex::TUI::Event
	def initialize(key:, raw:, timestamp: nil)
		super(timestamp:)
		@key = key
		@raw = raw
	end

	attr_reader :key
	attr_reader :raw

	def key?(*keys)
		keys.flatten.any? do |candidate|
			next false unless candidate

			candidate = candidate.to_sym if candidate.respond_to?(:to_sym)
			@key == candidate
		end
	end
end
