# frozen_string_literal: true

class Phlex::TUI::Tree
	def initialize(root: nil)
		@root = root || Phlex::TUI::Box.new(width: :fit, height: :fit, border: nil, padding: 0)
		@stack = [@root]
	end

	attr_reader :root
	attr_reader :stack

	def current_parent
		stack.last
	end

	def attach(node)
		current_parent.children << node
	end
end
