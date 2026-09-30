# frozen_string_literal: true

# Collects every local variable and parameter name a method mentions.
class Phlex::Compiler::LocalsScanner < Refract::Visitor
	def self.names(node)
		scanner = new
		scanner.visit(node)
		scanner.names
	end

	attr_reader :names

	def initialize
		super
		@names = Set.new
	end

	[
		Refract::LocalVariableReadNode,
		Refract::LocalVariableWriteNode,
		Refract::LocalVariableTargetNode,
		Refract::LocalVariableAndWriteNode,
		Refract::LocalVariableOrWriteNode,
		Refract::LocalVariableOperatorWriteNode,
		Refract::RequiredParameterNode,
		Refract::OptionalParameterNode,
		Refract::RestParameterNode,
		Refract::RequiredKeywordParameterNode,
		Refract::OptionalKeywordParameterNode,
		Refract::KeywordRestParameterNode,
		Refract::BlockParameterNode,
		Refract::BlockLocalVariableNode,
	].each do |node_class|
		visit node_class do |node|
			@names << node.name if node.name
			super(node)
		end
	end
end
