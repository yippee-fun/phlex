# frozen_string_literal: true

# Detects code that would change meaning if a block body were inlined into the
# enclosing scope: `return` anywhere, `next`, `break` and `redo` belonging to
# the block itself, or an assignment that would move a block local out of it.
class Phlex::Compiler::InlineScanner < Refract::Visitor
	def self.inlinable?(node)
		catch(:blocked) do
			new.visit(node)
			true
		end
	end

	def initialize
		super
		@blocks = 0
		@loops = 0
	end

	visit Refract::ReturnNode do |node|
		throw :blocked, false
	end

	[Refract::NextNode, Refract::BreakNode, Refract::RedoNode].each do |node_class|
		visit node_class do |node|
			throw :blocked, false if @blocks == 0 && @loops == 0
			super(node)
		end
	end

	[
		Refract::LocalVariableWriteNode,
		Refract::LocalVariableTargetNode,
		Refract::LocalVariableAndWriteNode,
		Refract::LocalVariableOrWriteNode,
		Refract::LocalVariableOperatorWriteNode,
	].each do |node_class|
		visit node_class do |node|
			throw :blocked, false if @blocks == 0
			super(node)
		end
	end

	[Refract::BlockNode, Refract::LambdaNode].each do |node_class|
		visit node_class do |node|
			@blocks += 1
			super(node)
			@blocks -= 1
		end
	end

	[Refract::WhileNode, Refract::UntilNode].each do |node_class|
		visit node_class do |node|
			visit node.predicate
			@loops += 1
			visit node.statements
			@loops -= 1
		end
	end

	# These bodies have scopes of their own, but their receivers are evaluated in
	# the block's.

	visit Refract::DefNode do |node|
		visit node.receiver
	end

	visit Refract::SingletonClassNode do |node|
		visit node.expression
	end
end
