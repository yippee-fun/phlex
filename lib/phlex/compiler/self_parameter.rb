# frozen_string_literal: true

# An element yields itself to its block, so in `svg do |s| s.path end` the
# parameter is the component. Rewrites the block's body so each element called
# on the parameter is a bare call the compiler can inline. Returns nil if the
# parameter is used any other way, or is shadowed or reassigned, or the body
# could see that it's gone.
class Phlex::Compiler::SelfParameter < Refract::MutationVisitor
	# Calls that can read the block's locals by name, with or without a receiver.
	SCOPE_CALLS = Set[:binding, :local_variables, :eval, :instance_eval, :class_eval, :module_eval, :send, :__send__, :public_send].freeze

	def self.rewrite(body, name, &element)
		catch(:used) { new(name, element).visit(body) }
	end

	def initialize(name, element)
		super()
		@name = name
		@element = element
		@rebindable = 0
	end

	# An element yields to its block with self unchanged, but a block passed
	# to anything else, `super` included, or a lambda, could run with another
	# self, where a bare call would reach a different object than the parameter.
	visit Refract::CallNode do |node|
		throw :used if SCOPE_CALLS.include?(node.name)

		if node.receiver in Refract::LocalVariableReadNode[name: ^@name]
			throw :used if node.safe_navigation || @rebindable > 0 || !@element.call(node.name)
			node.copy(receiver: nil, arguments: visit(node.arguments), block: visit(node.block))
		elsif node.receiver.nil? && @element.call(node.name)
			super(node)
		else
			node.copy(receiver: visit(node.receiver), arguments: visit(node.arguments), block: rebindable { visit(node.block) })
		end
	end

	visit Refract::SuperNode do |node|
		node.copy(arguments: visit(node.arguments), block: rebindable { visit(node.block) })
	end

	visit Refract::ForwardingSuperNode do |node|
		node.copy(block: rebindable { visit(node.block) })
	end

	visit Refract::LambdaNode do |node|
		rebindable { super(node) }
	end

	private def rebindable
		@rebindable += 1
		yield
	ensure
		@rebindable -= 1
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
			throw :used if node.name == @name
			super(node)
		end
	end
end
