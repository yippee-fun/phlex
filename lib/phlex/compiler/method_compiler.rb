# frozen_string_literal: true

module Phlex::Compiler
	class MethodCompiler < Refract::MutationVisitor
		ELEMENTS_SOURCE_PATH = Phlex::SGML::Elements.instance_method(:register_element).source_location[0]
		HELPERS_SOURCE_PATH = Phlex::SGML.instance_method(:plain).source_location[0]
		HELPER_OWNERS = Set[Phlex::SGML, Phlex::HTML, Phlex::SVG].freeze
		STATE_LOCAL = :__phlex_state__
		SELF_LOCAL = :__phlex_self__

		Attributes = Data.define(:hoisted, :nodes)
		NO_ATTRIBUTES = Attributes.new(hoisted: [], nodes: [])

		def initialize(component, path)
			super()
			@component = component
			@path = path
			@preamble = []
			@appends = 0
			@locals = 0
		end

		def compile(node)
			tree = visit(node)
			(@appends > 0) ? Compactor.new.visit(tree) : nil
		end

		visit Refract::ClassNode do |node|
			node
		end

		visit Refract::ModuleNode do |node|
			node
		end

		visit Refract::LambdaNode do |node|
			node
		end

		# A modifier form guards a single statement, so once its body compiles to
		# several it has to become a block form. A `begin` body already holds
		# several, and turning `begin … end while` into `while` would change it
		# from a post-test loop to a pre-test loop.
		[Refract::IfNode, Refract::UnlessNode, Refract::WhileNode, Refract::UntilNode].each do |modifier_node|
			visit modifier_node do |node|
				appends = @appends
				result = super(node)

				if node.inline && @appends > appends && !(node.statements in Refract::StatementsNode[body: [Refract::BeginNode]])
					result.copy(inline: false)
				else
					result
				end
			end
		end

		# Compiled code is evaluated under a path of its own, so `__FILE__` must
		# keep naming the real file.
		visit Refract::SourceFileNode do |node|
			Refract::StringNode.new(unescaped: @path)
		end

		# Generated locals all start with `__phlex_`, so a method that already uses
		# a name like that is left alone rather than risk a collision.
		visit Refract::DefNode do |node|
			return node unless @stack.size == 1
			return node if LocalsScanner.names(node).any? { |name| name.start_with?("__phlex_") }

			body = visit(node.body)

			node.copy(
				parameters: visit(node.parameters),
				body: Refract::BeginNode.new(
					statements: Refract::StatementsNode.new(body: [*@preamble, body]),
					rescue_clause: Refract::RescueNode.new(
						exceptions: [Refract::ConstantPathNode.new(name: "Exception")],
						reference: Refract::LocalVariableTargetNode.new(name: :__phlex_exception__),
						statements: Refract::StatementsNode.new(
							body: [
								Refract::CallNode.new(
									receiver: Refract::ConstantPathNode.new(name: "Kernel"),
									name: :raise,
									arguments: Refract::ArgumentsNode.new(
										arguments: [
											Refract::CallNode.new(
												name: :__map_exception__,
												arguments: Refract::ArgumentsNode.new(
													arguments: [Refract::LocalVariableReadNode.new(name: :__phlex_exception__)]
												)
											),
										]
									)
								),
							]
						),
						subsequent: nil
					),
					else_clause: nil,
					ensure_clause: nil
				)
			)
		end

		visit Refract::CallNode do |node|
			if statement?(node) && node.receiver.nil? && (compiled = compile_call(node))
				return compiled
			end

			super(node)
		end

		# A block passed to a method we don't know about might be evaluated against a
		# different receiver, so the compiled body is only used when self is unchanged.
		visit Refract::BlockNode do |node|
			return node unless node.body

			appends = @appends
			compiled = visit(node.body)
			return node if appends == @appends

			node.copy(
				body: Refract::StatementsNode.new(
					body: [
						Refract::IfNode.new(
							inline: false,
							predicate: Refract::CallNode.new(
								receiver: Refract::SelfNode.new,
								name: :equal?,
								arguments: Refract::ArgumentsNode.new(
									arguments: [Refract::LocalVariableReadNode.new(name: self_local)]
								)
							),
							statements: Refract::StatementsNode.new(body: [compiled]),
							subsequent: Refract::ElseNode.new(
								statements: Refract::StatementsNode.new(body: [node.body])
							)
						),
					]
				)
			)
		end

		private def statement?(node)
			Refract::StatementsNode === @stack[-2]
		end

		private def compile_call(node)
			if (element = element(node))
				element => [kind, tag]

				case kind
				in :void then compile_void_element(node, tag)
				in :standard then compile_standard_element(node, tag)
				end
			elsif helper?(node)
				case node.name
				in :plain then compile_plain(node)
				in :whitespace then compile_whitespace(node)
				in :doctype then compile_doctype(node)
				in :comment then compile_comment(node)
				in :fragment then compile_fragment(node)
				else nil
				end
			end
		end

		private def compile_standard_element(node, tag)
			attributes = compile_attributes(node, node.block ? ">" : "></#{tag}>")
			return compile_call_with_content(node) unless attributes

			Refract::StatementsNode.new(
				body: [
					*attributes.hoisted,
					raw("<#{tag}"),
					*attributes.nodes,
					raw(">"),
					*close_on_exit(compile_content(node.block), "</#{tag}>"),
					raw("</#{tag}>"),
					*(flush_after_head if tag == "head"),
				]
			)
		end

		private def compile_void_element(node, tag)
			return compile_call_with_content(node) if node.block

			attributes = compile_attributes(node, ">")
			return compile_call_with_content(node) unless attributes

			Refract::StatementsNode.new(
				body: [
					*attributes.hoisted,
					raw("<#{tag}"),
					*attributes.nodes,
					raw(">"),
				]
			)
		end

		# The runtime closes an element's tag however its content exits: an
		# exception, a `return`, a `throw`. Only content that can exit that way
		# needs the guard, and it sits between the opening and closing literals
		# so they still fuse with their neighbours on the normal path.
		private def close_on_exit(content, closing)
			return content if content.all? { |node| static?(node) }

			done = local(:done)

			[
				Refract::LocalVariableWriteNode.new(name: done, value: Refract::FalseNode.new),
				Refract::BeginNode.new(
					statements: Refract::StatementsNode.new(
						body: [*content, Refract::LocalVariableWriteNode.new(name: done, value: Refract::TrueNode.new)]
					),
					rescue_clause: nil,
					else_clause: nil,
					ensure_clause: Refract::EnsureNode.new(
						statements: Refract::StatementsNode.new(
							body: [
								Refract::UnlessNode.new(
									inline: false,
									predicate: Refract::LocalVariableReadNode.new(name: done),
									statements: Refract::StatementsNode.new(body: [raw(closing)]),
									else_clause: nil
								),
							]
						)
					)
				),
			]
		end

		private def static?(node)
			case node
			in Concat then Refract::StringNode === node.node
			in Refract::StatementsNode then node.body.all? { |child| static?(child) }
			else false
			end
		end

		private def flush_after_head
			[
				Refract::IfNode.new(
					inline: true,
					predicate: Refract::CallNode.new(
						receiver: Refract::LocalVariableReadNode.new(name: state_local),
						name: :should_render?
					),
					statements: Refract::StatementsNode.new(body: [Refract::CallNode.new(name: :flush)])
				),
			]
		end

		# Keeps the runtime call, but still compiles inside its block. Only for
		# methods that yield without changing self.
		private def compile_call_with_content(node)
			node.copy(
				arguments: visit(node.arguments),
				block: compile_block_unguarded(node.block)
			)
		end

		private def compile_block_unguarded(block)
			case block
			in Refract::BlockNode if block.body then block.copy(body: visit(block.body))
			else visit(block)
			end
		end

		private def compile_content(block)
			case block
			in nil
				[]
			in Refract::BlockNode if block.body.nil?
				[]
			in Refract::BlockNode if inlinable?(block)
				case block.body
				in Refract::StatementsNode[body:] if returns_nil?(body.last)
					[visit(block.body)]
				in Refract::StatementsNode[body: [statement]] if (content = compile_literal_content(statement))
					[content]
				in Refract::StatementsNode[body: [statement]] if pure?(statement)
					[implicit_output(statement)]
				else
					inline_dynamic_content(block.body)
				end
			in Refract::BlockNode
				[yield_content(compile_block_unguarded(block))]
			in Refract::BlockArgumentNode
				[yield_content(block)]
			end
		end

		private def inline_dynamic_content(body)
			buffer = local(:content_buffer)
			length = local(:content_length)
			content = local(:content)
			buffer_size = Refract::CallNode.new(
				receiver: Refract::LocalVariableReadNode.new(name: buffer),
				name: :bytesize
			)

			[
				Refract::LocalVariableWriteNode.new(
					name: buffer,
					value: Refract::CallNode.new(receiver: Refract::LocalVariableReadNode.new(name: state_local), name: :buffer)
				),
				Refract::LocalVariableWriteNode.new(name: length, value: buffer_size),
				Refract::LocalVariableWriteNode.new(name: content, value: Refract::ParenthesesNode.new(body: visit(body))),
				Refract::IfNode.new(
					inline: true,
					predicate: Refract::CallNode.new(
						receiver: Refract::LocalVariableReadNode.new(name: length),
						name: :==,
						arguments: Refract::ArgumentsNode.new(arguments: [buffer_size])
					),
					statements: Refract::StatementsNode.new(body: [implicit_output(Refract::LocalVariableReadNode.new(name: content))])
				),
			]
		end

		private def implicit_output(node)
			Refract::CallNode.new(
				name: :__implicit_output__,
				arguments: Refract::ArgumentsNode.new(arguments: [node])
			)
		end

		private def yield_content(block)
			Refract::CallNode.new(name: :__yield_content__, block:)
		end

		private def inlinable?(block)
			block.parameters.nil? && InlineScanner.inlinable?(block.body)
		end

		# Whether a statement's value is known to be nil, so the runtime's implicit
		# output of a block's return value can be skipped.
		private def returns_nil?(node)
			case node
			in nil | Refract::NilNode
				true
			in Refract::CallNode if node.receiver.nil?
				element(node) || (helper?(node) && node.name in :plain | :whitespace | :doctype | :comment | :fragment | :raw)
			in Refract::IfNode | Refract::UnlessNode
				returns_nil?(node.statements&.body&.last) && returns_nil?(node.subsequent)
			in Refract::ElseNode
				returns_nil?(node.statements&.body&.last)
			in Refract::CaseNode | Refract::CaseMatchNode
				node.conditions.all? { |condition| returns_nil?(condition.statements&.body&.last) } && returns_nil?(node.else_clause)
			else
				false
			end
		end

		# An interpolation that writes to the buffer changes what the runtime does
		# with the string, so only pure interpolations are compiled. They're
		# escaped as one expression, so the whole string is built before any of
		# it is appended, as at runtime.
		private def compile_literal_content(node)
			case node
			in Refract::StringNode | Refract::SymbolNode then plain(node.unescaped)
			in Refract::InterpolatedStringNode if pure?(node) then append(escaped(node))
			in Refract::NilNode then Refract::StatementsNode.new(body: [])
			else nil
			end
		end

		private def compile_attributes(node, closing)
			arguments = node.arguments&.arguments
			return NO_ATTRIBUTES if arguments.nil? || arguments.empty?
			return nil unless arguments in [Refract::KeywordHashNode => keyword_hash]

			if (static = static_attributes(keyword_hash))
				begin
					normalize_attributes(node.name, static)
					return Attributes.new(hoisted: [], nodes: [raw(Phlex::SGML::Attributes.generate_attributes(static))])
				rescue
					# Leave it to the runtime to raise, in case this code is never reached.
				end
			end

			hash = Refract::HashNode.new(elements: keyword_hash.elements)

			if pure?(hash)
				Attributes.new(hoisted: [], nodes: [append(close_tag_on_exception(attributes_call(node.name, hash), closing))])
			else
				local = local(:value)
				Attributes.new(
					hoisted: [Refract::LocalVariableWriteNode.new(name: local, value: visit(hash))],
					nodes: [append(close_tag_on_exception(attributes_call(node.name, Refract::LocalVariableReadNode.new(name: local)), closing))]
				)
			end
		end

		# The runtime closes the opening tag even when serialising the attributes
		# raises. Wrapping the expression itself keeps it inside the append chain.
		private def close_tag_on_exception(expression, closing)
			Refract::BeginNode.new(
				statements: Refract::StatementsNode.new(body: [expression]),
				rescue_clause: Refract::RescueNode.new(
					exceptions: [Refract::ConstantPathNode.new(name: "Exception")],
					reference: nil,
					statements: Refract::StatementsNode.new(
						body: [
							Refract::CallNode.new(
								receiver: Refract::CallNode.new(
									receiver: Refract::LocalVariableReadNode.new(name: state_local),
									name: :buffer
								),
								name: :<<,
								arguments: Refract::ArgumentsNode.new(arguments: [Refract::StringNode.new(unescaped: closing)])
							),
							Refract::CallNode.new(name: :raise),
						]
					),
					subsequent: nil
				),
				else_clause: nil,
				ensure_clause: nil
			)
		end

		private def attributes_call(element, hash)
			if (normalizer = Phlex::SGML::Elements::ATTRIBUTE_NORMALIZERS[element])
				hash = Refract::CallNode.new(
					receiver: Refract::ConstantPathNode.new(
						parent: Refract::ConstantPathNode.new(
							parent: Refract::ConstantPathNode.new(name: "Phlex"),
							name: "SGML"
						),
						name: "Elements"
					),
					name: normalizer,
					arguments: Refract::ArgumentsNode.new(arguments: [hash])
				)
			end

			Refract::CallNode.new(
				name: :__attributes__,
				arguments: Refract::ArgumentsNode.new(arguments: [hash])
			)
		end

		private def normalize_attributes(element, attributes)
			if (normalizer = Phlex::SGML::Elements::ATTRIBUTE_NORMALIZERS[element])
				Phlex::SGML::Elements.public_send(normalizer, attributes)
			end
		end

		private def static_attributes(keyword_hash)
			catch(:dynamic) { static_hash(keyword_hash.elements) }
		end

		private def static_hash(elements)
			elements.to_h do |element|
				throw :dynamic unless Refract::AssocNode === element
				throw :dynamic unless element.key in Refract::StringNode | Refract::SymbolNode
				[static_value(element.key), static_value(element.value)]
			end
		end

		private def static_value(node)
			case node
			in Refract::StringNode then node.unescaped
			in Refract::SymbolNode then node.unescaped.to_sym
			in Refract::IntegerNode | Refract::FloatNode then node.value
			in Refract::TrueNode then true
			in Refract::FalseNode then false
			in Refract::NilNode then nil
			in Refract::ArrayNode then node.elements.map { |element| static_value(element) }
			in Refract::HashNode then static_hash(node.elements)
			in Refract::CallNode if set_literal?(node) then Set.new(node.arguments.arguments.map { |element| static_value(element) })
			else throw :dynamic
			end
		end

		private def set_literal?(node)
			node.name == :[] && node.block.nil? && node.arguments && (
				(Refract::ConstantReadNode === node.receiver && node.receiver.name == :Set && unqualified_set_is_standard?) ||
				(Refract::ConstantPathNode === node.receiver && node.receiver.parent.nil? && node.receiver.name == :Set)
			)
		end

		# Whether a bare `Set` in the component resolves to the standard library's,
		# checking the lexical namespaces named by the class's constant path first.
		private def unqualified_set_is_standard?
			return @unqualified_set_is_standard if defined?(@unqualified_set_is_standard)

			names = @component.name.to_s.split("::")
			namespaces = (1...(names.length)).map { |depth| Object.const_get(names[0...depth].join("::")) }

			@unqualified_set_is_standard =
				namespaces.none? { |namespace| namespace.const_defined?(:Set, false) } &&
				@component.const_get(:Set).equal?(::Set)
		rescue NameError
			@unqualified_set_is_standard = false
		end

		# Whether evaluating the node can't have side effects or raise, so it's
		# safe to evaluate it inside an append that may be skipped. Constants are
		# excluded: reading one can autoload or raise NameError.
		private def pure?(node)
			case node
			in nil | Refract::StringNode | Refract::SymbolNode | Refract::IntegerNode | Refract::FloatNode |
				Refract::RationalNode | Refract::ImaginaryNode | Refract::RegularExpressionNode |
				Refract::TrueNode | Refract::FalseNode | Refract::NilNode | Refract::SelfNode |
				Refract::LocalVariableReadNode | Refract::InstanceVariableReadNode | Refract::EmbeddedVariableNode
				true
			in Refract::ArrayNode | Refract::HashNode | Refract::KeywordHashNode then node.elements.all? { |element| pure?(element) }
			in Refract::AssocNode then pure?(node.key) && pure?(node.value)
			in Refract::AssocSplatNode then pure?(node.value)
			in Refract::InterpolatedStringNode then node.parts.all? { |part| pure?(part) }
			in Refract::EmbeddedStatementsNode then pure?(node.statements)
			in Refract::ParenthesesNode then pure?(node.body)
			in Refract::StatementsNode then node.body.all? { |statement| pure?(statement) }
			else false
			end
		end

		private def compile_plain(node)
			case node.arguments&.arguments
			in [Refract::StringNode | Refract::SymbolNode => literal] then plain(literal.unescaped)
			in [Refract::InterpolatedStringNode => string] if pure?(string) then append(escaped(string))
			in [Refract::NilNode] then Refract::NilNode.new
			else nil
			end
		end

		private def compile_whitespace(node)
			return unless node.arguments.nil?

			case node.block
			in nil
				raw(" ")
			in Refract::BlockNode => block if (content = literal_block_content(block))
				Refract::StatementsNode.new(body: [raw(" "), content, raw(" ")])
			else
				compile_call_with_content(node)
			end
		end

		private def compile_comment(node)
			return unless node.arguments.nil?

			case node.block
			in Refract::BlockNode => block if (content = literal_block_content(block))
				Refract::StatementsNode.new(body: [raw("<!-- "), content, raw(" -->")])
			else
				compile_call_with_content(node)
			end
		end

		private def literal_block_content(block)
			return unless block.parameters.nil?
			return unless block.body in Refract::StatementsNode[body: [statement]]

			compile_literal_content(statement)
		end

		private def compile_doctype(node)
			return unless node.arguments.nil? && node.block.nil?

			raw("<!doctype html>")
		end

		private def compile_fragment(node)
			return unless node.block in Refract::BlockNode[parameters: nil]

			compile_call_with_content(node)
		end

		private def element(node)
			return unless node.receiver.nil?
			return unless (method = instance_method(node.name))

			owner = method.owner
			return unless owner.respond_to?(:__registered_elements__)
			return unless method.source_location&.first == ELEMENTS_SOURCE_PATH
			return unless (tag = owner.__registered_elements__[node.name])
			return if overridden_by_descendant?(node.name, owner)

			[owner.__registered_void_elements__.key?(node.name) ? :void : :standard, tag]
		end

		private def helper?(node)
			return false unless (method = instance_method(node.name))

			HELPER_OWNERS.include?(method.owner) &&
				method.source_location&.first == HELPERS_SOURCE_PATH &&
				!overridden_by_descendant?(node.name, method.owner)
		end

		# A compiled method is inherited, so it must not bake in a method that a
		# loaded subclass overrides.
		private def overridden_by_descendant?(name, owner)
			descendants.any? do |descendant|
				Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(descendant, name).owner != owner
			rescue NameError
				true
			end
		end

		private def descendants
			@descendants ||= descendants_of(@component)
		end

		private def descendants_of(component)
			component.subclasses.flat_map { |subclass| [subclass, *descendants_of(subclass)] }
		end

		private def instance_method(name)
			Phlex::UNBOUND_INSTANCE_METHOD_METHOD.bind_call(@component, name)
		rescue NameError
			nil
		end

		private def plain(value)
			raw(Phlex::Escape.html_escape(value))
		end

		private def raw(value)
			value => String

			append(Refract::StringNode.new(unescaped: value))
		end

		private def escaped(node)
			Refract::CallNode.new(
				receiver: Refract::ConstantPathNode.new(
					parent: Refract::ConstantPathNode.new(name: "Phlex"),
					name: "Escape"
				),
				name: :html_escape,
				arguments: Refract::ArgumentsNode.new(arguments: [node])
			)
		end

		# Appends a literal, or an expression that evaluates to a String.
		private def append(node)
			@appends += 1
			state_local

			Refract::StatementsNode.new(body: [Concat.new(node)])
		end

		private def local(purpose)
			:"__phlex_#{purpose}_#{@locals += 1}__"
		end

		private def state_local
			unless @state_local_set
				@preamble << Refract::LocalVariableWriteNode.new(
					name: STATE_LOCAL,
					value: Refract::InstanceVariableReadNode.new(name: :@_state)
				)
				@state_local_set = true
			end

			STATE_LOCAL
		end

		private def self_local
			unless @self_local_set
				@preamble << Refract::LocalVariableWriteNode.new(
					name: SELF_LOCAL,
					value: Refract::SelfNode.new
				)
				@self_local_set = true
			end

			SELF_LOCAL
		end
	end
end
