# frozen_string_literal: true

# Collects the names of calls Ruby would read as locals if a local of that name
# were declared: `foo`, and the value of the shorthand `foo:`.
class Phlex::Compiler::BareCallScanner < Refract::Visitor
	def self.names(node)
		scanner = new
		scanner.visit(node)
		scanner.names
	end

	def self.bare?(node)
		Refract::CallNode === node && node.receiver.nil? && node.arguments.nil?
	end

	attr_reader :names

	def initialize
		super
		@names = Set.new
	end

	visit Refract::CallNode do |node|
		@names << node.name if node.variable_call
		super(node)
	end

	visit Refract::ImplicitNode do |node|
		@names << node.value.name if self.class.bare?(node.value)
		super(node)
	end
end
