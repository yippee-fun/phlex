# frozen_string_literal: true

# Detects a `break` belonging to a block, which makes the call it's passed to
# return the break's value.
class Phlex::Compiler::BreakScanner < Refract::Visitor
	def self.breaks?(node)
		catch(:break) do
			new.visit(node)
			false
		end
	end

	visit Refract::BreakNode do |node|
		throw :break, true
	end

	# A `break` in these belongs to them.
	[Refract::BlockNode, Refract::LambdaNode, Refract::WhileNode, Refract::UntilNode].each do |node_class|
		visit node_class do |node|
			nil
		end
	end
end
