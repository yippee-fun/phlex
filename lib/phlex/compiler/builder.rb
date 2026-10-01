# frozen_string_literal: true

# Constructors for the Refract nodes the compiler generates, with the
# defaults it always wants. Bodies are given as arrays of statements.
module Phlex::Compiler::Builder
	private def call(receiver, name, *arguments, block: nil)
		Refract::CallNode.new(
			receiver:,
			name:,
			arguments: arguments.empty? ? nil : Refract::ArgumentsNode.new(arguments:),
			block:
		)
	end

	# Looked up from the top level, so a component can't shadow it.
	private def constant(path)
		path.split("::").reduce(nil) { |parent, name| Refract::ConstantPathNode.new(parent:, name:) }
	end

	private def string(text)
		Refract::StringNode.new(unescaped: text)
	end

	private def read(name)
		Refract::LocalVariableReadNode.new(name:)
	end

	private def write(name, value)
		Refract::LocalVariableWriteNode.new(name:, value:)
	end

	private def statements(body)
		Refract::StatementsNode.new(body:)
	end

	private def parenthesized(body)
		Refract::ParenthesesNode.new(body: statements(body))
	end

	private def if_node(predicate, body, else_body: nil, inline: false)
		Refract::IfNode.new(
			inline:,
			predicate:,
			statements: statements(body),
			subsequent: else_body && Refract::ElseNode.new(statements: statements(else_body))
		)
	end

	private def unless_node(predicate, body, inline: false)
		Refract::UnlessNode.new(inline:, predicate:, statements: statements(body), else_clause: nil)
	end

	private def begin_node(body, rescue_clause: nil, ensure_clause: nil)
		Refract::BeginNode.new(statements: statements(body), rescue_clause:, else_clause: nil, ensure_clause:)
	end

	private def rescue_node(exceptions, reference, body)
		Refract::RescueNode.new(exceptions:, reference:, statements: statements(body), subsequent: nil)
	end

	private def ensure_node(body)
		Refract::EnsureNode.new(statements: statements(body))
	end
end
