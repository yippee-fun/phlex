# frozen_string_literal: true

class Phlex::Compiler::ClassCompiler < Refract::Visitor
	attr_reader :visibilities

	def initialize(environment, path, diagnostics: Phlex::Compiler::Diagnostics.new(path))
		super()
		@environment = environment
		@component = environment.component
		@path = path
		@diagnostics = diagnostics
		@definitions = []
		@compiled_snippets = []
		@visibilities = {}
	end

	def compile(node)
		visit(node.body)

		# Two definitions of a method on one line share a source location, so
		# neither can be told apart from the live method.
		@definitions.group_by { |definition| [definition.name, definition.start_line] }.each_value do |definitions|
			if definitions.one?
				compile_definition(definitions.first)
			else
				@diagnostics.report(definitions.first, "#{definitions.first.name} isn't compiled because it's defined more than once on this line")
			end
		end

		@compiled_snippets.freeze
	end

	visit Refract::DefNode do |node|
		return if node.name == :initialize
		return if node.receiver

		@definitions << node
	end

	visit Refract::ClassNode do |node|
		nil
	end

	visit Refract::ModuleNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end

	private def compile_definition(node)
		method = begin
			Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, node.name)
		rescue NameError
			nil
		end

		unless method
			@diagnostics.report(node, "#{node.name} isn't compiled because #{@component} has no such method")
			return
		end

		path, lineno = method.source_location

		if Phlex::Compiler::MAP.key?(path)
			@diagnostics.report(node, "#{node.name} is already compiled")
			return
		end

		unless @path == path && node.start_line == lineno
			@diagnostics.report(node, "#{node.name} isn't compiled because the live method is defined at #{path}:#{lineno}")
			return
		end

		compiled = Phlex::Compiler::MethodCompiler.new(@environment, @path, diagnostics: @diagnostics).compile(node)
		return unless compiled

		@compiled_snippets << compiled
		@visibilities[node.name] = visibility_of(node.name)
	end

	private def visibility_of(name)
		if @component.private_instance_methods(false).include?(name)
			:private
		elsif @component.protected_instance_methods(false).include?(name)
			:protected
		else
			:public
		end
	end
end
