# frozen_string_literal: true

# Merges runs of adjacent appends into a single guarded buffer append.
class Phlex::Compiler::Compactor < Refract::MutationVisitor
	visit Refract::StatementsNode do |node|
		queue = node.body.compact.reverse
		results = []
		parts = nil

		while (child = queue.pop)
			case child
			in Refract::StatementsNode
				child.body.compact.reverse_each { |n| queue << n }
			in Phlex::Compiler::Concat
				if parts
					parts << child.node
				else
					parts = [child.node]
					results << parts
				end
			else
				if (resolved = visit(child))
					parts = nil
					results << resolved
				end
			end
		end

		node.copy(
			body: results.map { |result| (Array === result) ? append(result) : result }
		)
	end

	private def append(parts)
		merged = parts.each_with_object([]) do |part, acc|
			if Refract::StringNode === part && Refract::StringNode === acc.last
				acc[-1] = Refract::StringNode.new(unescaped: acc.last.unescaped + part.unescaped)
			else
				acc << part
			end
		end

		state = Refract::LocalVariableReadNode.new(name: Phlex::Compiler::MethodCompiler::STATE_LOCAL)

		# Each part is appended in its own `<<` so that if a dynamic part raises,
		# everything before it has already reached the buffer, as at runtime.
		chain = merged.reduce(Refract::CallNode.new(receiver: state, name: :buffer)) do |receiver, part|
			Refract::CallNode.new(
				receiver:,
				name: :<<,
				arguments: Refract::ArgumentsNode.new(arguments: [part])
			)
		end

		Refract::ParenthesesNode.new(
			body: Refract::StatementsNode.new(
				body: [
					Refract::IfNode.new(
						inline: false,
						predicate: Refract::CallNode.new(receiver: state, name: :should_render?),
						statements: Refract::StatementsNode.new(body: [chain])
					),
					Refract::NilNode.new,
				]
			)
		)
	end
end
