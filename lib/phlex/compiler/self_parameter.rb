# frozen_string_literal: true

# An element yields itself to its block, so in `svg do |s| s.path end` the
# parameter is the component. Rewrites the block's body so each element called
# on the parameter is a bare call the compiler can inline. Returns nil if the
# parameter is used any other way, or is shadowed or reassigned, or the body
# could see that it's gone.
class Phlex::Compiler::SelfParameter < Refract::MutationVisitor
	SCOPE_CALLS = Set[:binding, :local_variables, :eval].freeze

	def self.rewrite(body, name, &element)
		catch(:used) { new(name, element).visit(body) }
	end

	def initialize(name, element)
		super()
		@name = name
		@element = element
	end

	visit Refract::CallNode do |node|
		case node
		in { receiver: Refract::LocalVariableReadNode[name: ^@name], safe_navigation: nil | false }
			throw :used unless @element.call(node.name)
			super(node.copy(receiver: nil))
		in { receiver: nil, name: } if SCOPE_CALLS.include?(name)
			throw :used
		else
			super(node)
		end
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
