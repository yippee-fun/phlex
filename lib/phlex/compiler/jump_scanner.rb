# frozen_string_literal: true

# Detects control flow that would change meaning if a block body were inlined:
# `return` anywhere, or `next`, `break` and `redo` belonging to the block itself.
class Phlex::Compiler::JumpScanner < Refract::Visitor
	def self.jumps?(node)
		scanner = new
		scanner.visit(node)
		scanner.jumps
	end

	attr_reader :jumps

	def initialize
		super
		@depth = 0
		@jumps = false
	end

	visit Refract::ReturnNode do |node|
		@jumps = true
	end

	visit Refract::NextNode do |node|
		@jumps = true if @depth == 0
	end

	visit Refract::BreakNode do |node|
		@jumps = true if @depth == 0
	end

	visit Refract::RedoNode do |node|
		@jumps = true if @depth == 0
	end

	visit Refract::BlockNode do |node|
		@depth += 1
		super(node)
		@depth -= 1
	end

	visit Refract::LambdaNode do |node|
		@depth += 1
		super(node)
		@depth -= 1
	end

	visit Refract::DefNode do |node|
		nil
	end
end
