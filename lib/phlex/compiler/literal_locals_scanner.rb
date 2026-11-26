# frozen_string_literal: true

# Finds the locals a method assigns only once, to a literal that's the same
# object every time it's evaluated, which compiled code can expect them to
# hold. A local named in any other way, such as a parameter or a target, is
# left out, however deeply it's nested.
class Phlex::Compiler::LiteralLocalsScanner < Refract::Visitor
	FIXNUM = -(2 ** 62)...(2 ** 62)

	def self.literals(node)
		scanner = new
		scanner.visit(node)
		scanner.literals
	end

	def initialize
		super
		@writes = Hash.new { |hash, name| hash[name] = [] }
	end

	def literals
		@writes.filter_map { |name, values| [name, values.first] if values.length == 1 && literal?(values.first) }.to_h
	end

	visit Refract::LocalVariableWriteNode do |node|
		@writes[node.name] << node.value
		super(node)
	end

	[
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
			@writes[node.name] << nil if node.name
			super(node)
		end
	end

	private def literal?(node)
		case node
		in Refract::SymbolNode | Refract::NilNode | Refract::TrueNode | Refract::FalseNode then true
		in Refract::IntegerNode then FIXNUM.cover?(node.value)
		in Refract::FloatNode then node.prism_node&.value&.finite? || false
		in Refract::StringNode then node.prism_node&.frozen? || false
		else false
		end
	end
end
