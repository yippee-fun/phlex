# frozen_string_literal: true

# Finds code in a block body that would behave differently if Ruby parsed it a
# second time with the block's locals already declared, as it does the original
# body kept after the compiled one. Code with state of its own, a flip-flop, a
# regular expression interpolated only once or a method definition, would also
# be split between the two copies.
class Phlex::Compiler::ReparseScanner < Refract::Visitor
	NUMBERED_PARAMETERS = (1..9).map { |n| :"_#{n}" }.freeze

	# The names a parameter list declares as parameters, but not locals assigned
	# in their defaults.
	class ParameterNames < Refract::Visitor
		def self.of(parameters)
			scanner = new
			scanner.visit(parameters)
			scanner.names
		end

		attr_reader :names

		def initialize
			super
			@names = Set.new
		end

		[
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
			end
		end
	end

	def self.conflict(block)
		scanner = new(block.parameters)
		scanner.visit(block.body)
		scanner.conflict
	end

	def initialize(parameters)
		super()
		@own = ParameterNames.of(parameters)
		@own.merge(NUMBERED_PARAMETERS) if Refract::NumberedParametersNode === parameters
		@uses = {}
		@stateful = nil
		@scopes = []
	end

	def conflict
		return @stateful if @stateful

		@uses.each do |name, reason|
			return reason if @own.include?(name)
		end

		nil
	end

	visit Refract::CallNode do |node|
		use(node.name, "`#{node.name}` is called before it's assigned") if node.variable_call
		super(node)
	end

	visit Refract::ImplicitNode do |node|
		if Phlex::Compiler::BareCallScanner.bare?(node.value)
			use(node.value.name, "`#{node.value.name}` is called before it's assigned")
		end

		super(node)
	end

	visit Refract::ItLocalVariableReadNode do |node|
		use(:it, "`it` is assigned after it's read as a parameter")
	end

	[
		Refract::LocalVariableReadNode,
		Refract::LocalVariableWriteNode,
		Refract::LocalVariableTargetNode,
		Refract::LocalVariableAndWriteNode,
		Refract::LocalVariableOrWriteNode,
		Refract::LocalVariableOperatorWriteNode,
	].each do |node_class|
		visit node_class do |node|
			super(node)
			owner = @scopes.size - node.depth

			if owner == 0
				@own << node.name
			elsif owner > 0 && !@scopes[owner - 1].include?(node.name)
				use(node.name, "`#{node.name}` is a local of both the block and a block inside it")
			end
		end
	end

	[Refract::BlockNode, Refract::LambdaNode].each do |node_class|
		visit node_class do |node|
			@scopes.push(ParameterNames.of(node.parameters))
			super(node)
			@scopes.pop
		end
	end

	visit Refract::FlipFlopNode do |node|
		@stateful ||= "it has a flip-flop"
		super(node)
	end

	[Refract::InterpolatedRegularExpressionNode, Refract::InterpolatedMatchLastLineNode].each do |node_class|
		visit node_class do |node|
			@stateful ||= "a regular expression in it is interpolated only once" if node.once
			super(node)
		end
	end

	[Refract::DefNode, Refract::SingletonClassNode].each do |node_class|
		visit node_class do |node|
			@stateful ||= "it defines methods"
		end
	end

	private def use(name, reason)
		@uses[name] ||= reason
	end
end
