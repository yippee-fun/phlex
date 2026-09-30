# frozen_string_literal: true

# Inlining a block must not move its local assignments into the enclosing scope.
class Phlex::Compiler::BlockLocalsScanner < Refract::Visitor
	def self.writes?(node)
		catch(:writes) do
			new.visit(node)
			false
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
			throw :writes, true
		end
	end

	[Refract::BlockNode, Refract::LambdaNode, Refract::DefNode, Refract::ClassNode, Refract::ModuleNode].each do |node_class|
		visit node_class do |node|
			nil
		end
	end
end
