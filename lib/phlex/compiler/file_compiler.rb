# frozen_string_literal: true

class Phlex::Compiler::FileCompiler < Refract::Visitor
	Result = Data.define(:namespace, :component, :compiled_snippets, :visibilities)

	def initialize(path)
		super()
		@path = path
		@current_namespace = []
		@nesting = []
		@results = []
	end

	def compile(node)
		visit(node)
		@results.freeze
	end

	visit Refract::ModuleNode do |node|
		enter(node) { super(node) }
	end

	visit Refract::ClassNode do |node|
		enter(node) do
			if (component = current_component)
				environment = Phlex::Compiler::Environment.new(component, nesting: @nesting.dup.freeze)
				class_compiler = Phlex::Compiler::ClassCompiler.new(environment, @path)

				@results << Result.new(
					namespace: @current_namespace.dup.freeze,
					component:,
					compiled_snippets: class_compiler.compile(node),
					visibilities: class_compiler.visibilities
				)
			end

			# Components can be nested inside other classes, components included.
			super(node)
		end
	end

	visit Refract::DefNode do |node|
		nil
	end

	visit Refract::BlockNode do |node|
		nil
	end

	# Tracks both the lexical scope nodes, for reopening the class in the
	# compiled source, and the modules they name, resolved as Ruby would.
	private def enter(node)
		@current_namespace.push(node)
		@nesting.push(resolve(node.constant_path))
		yield
	ensure
		@nesting.pop
		@current_namespace.pop
	end

	private def current_component
		const = @nesting.last
		const if Class === const && Phlex::SGML > const && !const.frozen?
	end

	private def resolve(constant_path)
		case constant_path
		in Refract::ConstantReadNode[name:] then lexical_lookup(name)
		in Refract::ConstantPathNode[parent: nil, name:] then Object.const_get(name, false)
		in Refract::ConstantPathNode[parent:, name:] then (scope = resolve(parent)) && scoped_lookup(scope, name)
		end
	rescue NameError
		nil
	end

	# A bare constant is looked up in each enclosing scope, innermost first,
	# then in the innermost scope's ancestors.
	private def lexical_lookup(name)
		@nesting.reverse_each do |scope|
			return scope.const_get(name, false) if scope&.const_defined?(name, false)
		end

		(@nesting.last || Object).const_get(name)
	end

	# `A::B` is looked up in A and its ancestors, but not at the top level
	# unless A is Object.
	private def scoped_lookup(scope, name)
		scope.ancestors.each do |ancestor|
			break if ancestor == Object && scope != Object
			return ancestor.const_get(name, false) if ancestor.const_defined?(name, false)
		end

		nil
	end
end
