# frozen_string_literal: true

module Phlex::Compiler
	class InsertNode
		def initialize(&block)
			@block = block
		end

		attr_reader :block

		def accept(visitor)
			visitor.visit_insert_node(self)
		end
	end
end
