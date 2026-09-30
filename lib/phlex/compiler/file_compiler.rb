# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Refract::Visitor
	Result = Data.define(:namespace, :component, :compiled_snippets, :visibilities)

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

		if (component = current_component)
			class_compiler = Phlex::Compiler::ClassCompiler.new(component, @path)

			@results << Result.new(
				namespace: @current_namespace.dup.freeze,
				component:,
				compiled_snippets: class_compiler.compile(node),
				visibilities: class_compiler.visibilities
			)
		end

		# Components can be nested inside other classes, components included.
		super(node)

		@current_namespace.pop
	end

	visit Refract::DefNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end

	private def current_component
		constant_name = @current_namespace.reduce(nil) do |namespace, scope|
			name = Refract::Formatter.new.format_node(scope.constant_path).source
			(namespace && !name.start_with?("::")) ? "#{namespace}::#{name}" : name
		end

		const = eval(constant_name, TOPLEVEL_BINDING)
		const if Class === const && Phlex::SGML > const && !const.frozen?
	rescue NameError
		nil
	end
end
