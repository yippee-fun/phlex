# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Refract::Visitor
	Result = Data.define(:namespace, :compiled_snippets)

	def initialize(path)
		super()
		@path = path
		@current_namespace = []
		@results = []
	end

	def compile(node)
		visit(node)
		@results.freeze
	end

	visit Refract::ModuleNode do |node|
		@current_namespace.push(node)
		super(node)
		@current_namespace.pop
	end

	visit Refract::ClassNode do |node|
		@current_namespace.push(node)

		namespace = @current_namespace.map do |node|
			Refract::Formatter.new.format_node(node.constant_path).source
		end.join("::")

		const = eval(namespace, TOPLEVEL_BINDING)

		if Class === const && Phlex::SGML > const
			@results << Result.new(
				namespace: @current_namespace.dup.freeze,
				compiled_snippets: Phlex::Compiler::ClassCompiler.new(const, @path).compile(node)
			)
		else
			super(node)
		end

		@current_namespace.pop
	end

	visit Refract::DefNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end
end
