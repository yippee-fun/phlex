# frozen_string_literal: true

module Phlex::Compiler
	# Rewrites one method so that the element and helper calls it makes become
	# output nodes in its tree, which the Emitter then lowers to buffer appends.
	class MethodCompiler < Refract::MutationVisitor
		include Builder

		Attributes = Data.define(:hoisted, :parts)
		NO_ATTRIBUTES = Attributes.new(hoisted: [], parts: [])

		# A part of the opening tag that runs a serialiser, which can raise.
		Serialized = Data.define(:node)

		TokenChoice = Data.define(:condition, :truthy, :falsy)
		TOKEN_CONDITIONS_LIMIT = 3

		UNINLINABLE_BLOCK = "it has parameters or contains a return, break, next or local assignment"
		GUARDED_BLOCK_DEPTH_LIMIT = 4

		def initialize(environment, path, diagnostics: Diagnostics.new(path))
			super()
			@environment = environment
			@path = path
			@diagnostics = diagnostics
			@locals = Locals.new
			@preamble = []
			@appends = 0
			@guarded_blocks = 0
			@compiling_calls = true
		end

		# Returns nil when there's nothing to compile, unless the method is being
		# recompiled, when the definition must still replace the compiled one.
		def compile(node, keep_uncompiled: false)
			tree = visit(node)
			return tree if @appends == 0 && keep_uncompiled
			return nil if @appends == 0

			Emitter.new(@locals).visit(tree)
		end

		visit Refract::ClassNode do |node|
			node
		end

		visit Refract::ModuleNode do |node|
			node
		end

		visit Refract::LambdaNode do |node|
			without_compiling_calls { super(node) }
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
			string(@path)
		end

		# Generated locals all start with `__phlex_`, so a method that already uses
		# a name like that is refused rather than risk a collision. Parameter
		# defaults run before the body, so before the state local exists, so
		# element calls in them stay as calls.
		visit Refract::DefNode do |node|
			return node unless @stack.size == 1

			if (reserved = (LocalsScanner.names(node) | BareCallScanner.names(node)).find { |name| name.start_with?("__phlex_") })
				@diagnostics.refuse(node, "#{reserved} is a name the compiler reserves for locals; names starting with __phlex_ can't be used")
				return node
			end

			parameters = without_compiling_calls(because: "it's in a parameter default") { visit(node.parameters) }
			body = visit(node.body)

			node.copy(
				parameters:,
				body: mapping_exceptions([*@preamble, body])
			)
		end

		visit Refract::CallNode do |node|
			if @compiling_calls
				if statement?(node) && node.receiver.nil? && (compiled = compile_call(node))
					return compiled
				end
			elsif @uncompiled_because && node.receiver.nil? && (@environment.element(node.name) || @environment.helper?(node.name))
				keep_call(node, @uncompiled_because)
			end

			super(node)
		end

		# A block passed to a method we don't know about might be evaluated against a
		# different receiver, so the compiled body is only used when self is
		# unchanged, and the original is kept for when it isn't. Each level of
		# nesting repeats the original bodies inside it, so past a few levels the
		# calls are left alone.
		#
		# The block may outlive the method or be built before rendering starts, so
		# the compiled body reads the state afresh rather than trusting the one
		# read on entry, and the block maps its own exceptions, as the method's
		# rescue may no longer be on the stack.
		visit Refract::BlockNode do |node|
			return super(node) unless @compiling_calls
			return without_compiling_calls { super(node) } unless node.body

			if @guarded_blocks == GUARDED_BLOCK_DEPTH_LIMIT
				@diagnostics.report(node, "calls in this block are left to the runtime because it's nested #{GUARDED_BLOCK_DEPTH_LIMIT} blocks deep")
				return mapping_block_exceptions(without_compiling_calls { super(node) })
			end

			if (conflict = ReparseScanner.conflict(node))
				@diagnostics.report(node, "calls in this block are left to the runtime because #{conflict}")
				return mapping_block_exceptions(without_compiling_calls { super(node) })
			end

			appends = @appends
			@guarded_blocks += 1
			compiled = visit(node.body)
			@guarded_blocks -= 1
			return mapping_block_exceptions(without_compiling_calls { super(node) }) if appends == @appends

			original = without_compiling_calls { visit(node.body) }

			node.copy(
				parameters: without_compiling_calls(because: "it's in a parameter default") { visit(node.parameters) },
				body: statements([
					mapping_exceptions([
						if_node(
							call(read(self_local), :__phlex_equal__?, Refract::SelfNode.new),
							[write(Locals::STATE, Refract::InstanceVariableReadNode.new(name: :@_state)), compiled],
							else_body: [original]
						),
					]),
				])
			)
		end

		private def mapping_block_exceptions(block)
			block.copy(body: statements([mapping_exceptions([block.body])]))
		end

		private def mapping_exceptions(body)
			begin_node(
				body,
				rescue_clause: rescue_node(
					[constant("Exception")],
					Refract::LocalVariableTargetNode.new(name: Locals::EXCEPTION, depth: nil),
					[call(constant("Kernel"), :raise, call(constant("Phlex"), :__map_exception__, read(Locals::EXCEPTION)))]
				)
			)
		end

		private def statement?(node)
			Refract::StatementsNode === @stack[-2]
		end

		# Visits code whose calls must stay as they are, so only `__FILE__` is
		# rewritten. Element and helper calls found there are reported with the
		# reason, unless the code is a copy of something compiled elsewhere.
		private def without_compiling_calls(because: nil)
			compiling_calls, uncompiled_because = @compiling_calls, @uncompiled_because
			@compiling_calls = false
			@uncompiled_because = because
			yield
		ensure
			@compiling_calls, @uncompiled_because = compiling_calls, uncompiled_because
		end

		# A call lowered to output, or kept with output compiled inside its block,
		# relies on the method meaning what it did at compile time. A call kept
		# as it was, with nothing compiled inside, doesn't.
		private def compile_call(node)
			appends = @appends

			compiled = if (element = @environment.element(node.name))
				element.void ? compile_void_element(node, element.tag) : compile_standard_element(node, element.tag)
			elsif @environment.helper?(node.name)
				case node.name
				in :plain then compile_plain(node)
				in :raw then compile_raw(node)
				in :whitespace then compile_whitespace(node)
				in :doctype then compile_doctype(node)
				in :comment then compile_comment(node)
				in :fragment then compile_fragment(node)
				else nil
				end
			end

			@environment.inlined << node.name if compiled && (@appends > appends || !(Refract::CallNode === compiled))
			compiled
		end

		# The runtime closes the element however its content exits, which the
		# enclosure reproduces. Only the method's own block is forwarded inline,
		# since another expression is evaluated, and may be nil, when the
		# element is called.
		private def compile_standard_element(node, tag)
			if Refract::BlockArgumentNode === node.block
				return compile_forwarded_element(node, tag) if node.block.expression.nil? && tag != "head"

				return compile_call_with_content(node, because: "its block is forwarded")
			end

			attributes = compile_attributes(node, node.block ? ">" : "></#{tag}>")
			return compile_call_with_content(node, because: "it has positional arguments") unless attributes

			statements([
				*attributes.hoisted,
				append(literal("<#{tag}"), *attributes.parts, literal(">")),
				Output::Enclosed.new(body: compile_content(node, element: true), closing: "</#{tag}>"),
				raw("</#{tag}>"),
				*(flush_after_head if tag == "head"),
			])
		end

		# An element given the method's block, as the element method does it: the
		# buffer and whether to render are read when it's called, the block is
		# only yielded if there is one, and without one the element is empty.
		private def compile_forwarded_element(node, tag)
			attributes = compile_attributes(node, ">")
			return compile_call_with_content(node, because: "it has positional arguments") unless attributes

			buffer = @locals.fresh(:buffer)
			length = @locals.fresh(:content_length)
			content = @locals.fresh(:content)
			empty = attributes.parts.map { |part| (Output::Guarded === part) ? part.with(closing: "></#{tag}>") : part }

			statements([
				*attributes.hoisted,
				write(buffer, call(read(state_local), :buffer)),
				if_node(
					call(nil, :block_given?),
					[
						if_node(
							should_render,
							[
								opening(buffer, literal("<#{tag}"), *attributes.parts, literal(">")),
								begin_node(
									[
										write(length, call(read(state_local), :output_bytesize)),
										write(content, yield_self),
										if_node(call(read(length), :==, call(read(state_local), :output_bytesize)), [element_value_output(read(content), read(buffer))]),
									],
									ensure_clause: ensure_node([call(read(buffer), :<<, string("</#{tag}>"))])
								),
							],
							else_body: [yield_self]
						),
					],
					else_body: [if_node(should_render, [opening(buffer, literal("<#{tag}"), *empty, literal("></#{tag}>"))])]
				),
				Refract::NilNode.new,
			])
		end

		private def yield_self
			Refract::YieldNode.new(arguments: Refract::ArgumentsNode.new(arguments: [Refract::SelfNode.new]))
		end

		# How an element method outputs its block's value.
		private def element_value_output(content, buffer)
			formatted = @locals.fresh(:formatted)

			elsif_chain(
				[call(constant("Phlex::SGML::SafeObject"), :===, content), call(read(state_local), :append, call(content, :to_s))],
				[call(constant("String"), :===, content), call(buffer, :<<, escaped(content))],
				[call(constant("Symbol"), :===, content), call(buffer, :<<, escaped(call(content, :name)))],
				[call(Refract::NilNode.new, :equal?, content), Refract::NilNode.new],
				otherwise: if_node(write(formatted, call(nil, :format_object, content)), [call(buffer, :<<, escaped(read(formatted)))])
			)
		end

		private def compile_void_element(node, tag)
			return compile_call_with_content(node, because: "it's a void element given a block") if node.block

			attributes = compile_attributes(node, ">")
			return compile_call_with_content(node, because: "it has positional arguments") unless attributes

			statements([
				*attributes.hoisted,
				append(literal("<#{tag}"), *attributes.parts, literal(">")),
			])
		end

		private def flush_after_head
			[if_node(should_render, [call(nil, :flush)], inline: true)]
		end

		# Keeps the runtime call, but still compiles inside its block. Only for
		# methods that yield without changing self.
		private def compile_call_with_content(node, because: nil)
			keep_call(node, because) if because

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

		private def compile_content(node, element: false)
			case node.block
			in nil
				[]
			in Refract::BlockNode => block if block.body.nil?
				[]
			in Refract::BlockNode => block if inlinable?(block)
				case block.body
				in Refract::StatementsNode[body:] if returns_nil?(body.last)
					[visit(block.body)]
				in Refract::StatementsNode[body: [statement]] if (content = compile_literal_content(statement))
					[content]
				in Refract::StatementsNode[body: [Refract::LocalVariableReadNode | Refract::InstanceVariableReadNode => variable]] if element
					[element_output(variable)]
				in Refract::StatementsNode[body: [statement]] if pure?(statement)
					[implicit_output(statement)]
				else
					inline_dynamic_content(block.body)
				end
			in Refract::BlockNode => block
				@diagnostics.report(node, "#{node.name}'s block is yielded at runtime because #{UNINLINABLE_BLOCK}")
				[yield_content(compile_block_unguarded(block))]
			end
		end

		# The runtime outputs a block's value only if the block wrote nothing.
		private def inline_dynamic_content(body)
			length = @locals.fresh(:content_length)
			content = @locals.fresh(:content)

			[
				write(length, call(read(state_local), :output_bytesize)),
				write(content, Refract::ParenthesesNode.new(body: visit(body))),
				if_node(call(read(length), :==, call(read(state_local), :output_bytesize)), [implicit_output(read(content))], inline: true),
			]
		end

		# An element outputs its block's value itself rather than calling
		# __implicit_output__, so a String is escaped inline.
		private def element_output(variable)
			elsif_chain(
				[call(constant("Phlex::SGML::SafeObject"), :===, variable), implicit_output(variable)],
				[call(constant("String"), :===, variable), append(expression(escaped(variable)))],
				otherwise: implicit_output(variable)
			)
		end

		private def implicit_output(node)
			call(nil, :__implicit_output__, node)
		end

		private def yield_content(block)
			call(nil, :__yield_content__, block:)
		end

		private def inlinable?(block)
			block.parameters.nil? && InlineScanner.inlinable?(block.body)
		end

		# Whether a statement's value is known to be nil, so the runtime's implicit
		# output of a block's return value can be skipped. The elements and
		# helpers that answer is built on are recorded as relied on, but only
		# when the answer is yes, since otherwise nothing is built on them.
		private def returns_nil?(node)
			relied = []
			known = nil_valued?(node, relied)
			@environment.inlined.merge(relied) if known
			known
		end

		private def nil_valued?(node, relied)
			case node
			in nil | Refract::NilNode
				true
			in Refract::CallNode if node.receiver.nil?
				known = @environment.element(node.name) || (@environment.helper?(node.name) && node.name in :plain | :whitespace | :doctype | :comment | :fragment | :raw) || render_returns_nil?(node)
				relied << node.name if known
				known
			in Refract::IfNode
				nil_valued?(node.statements&.body&.last, relied) && nil_valued?(node.subsequent, relied)
			in Refract::UnlessNode
				nil_valued?(node.statements&.body&.last, relied) && nil_valued?(node.else_clause, relied)
			in Refract::ElseNode
				nil_valued?(node.statements&.body&.last, relied)
			in Refract::CaseNode | Refract::CaseMatchNode
				node.conditions.all? { |condition| nil_valued?(condition.statements&.body&.last, relied) } && nil_valued?(node.else_clause, relied)
			else
				false
			end
		end

		# `render` returns nil, unless a `break` in its block, or in a default for
		# one of the block's parameters, returns from it.
		private def render_returns_nil?(node)
			node.name == :render && @environment.helper?(:render) && case node.block
				in nil then true
				in Refract::BlockNode => block then [block.parameters, block.body].compact.none? { |part| BreakScanner.breaks?(part) }
				else false
			end
		end

		# An interpolation that writes to the buffer changes what the runtime does
		# with the string, so only pure interpolations are compiled. They're
		# escaped as one expression, so the whole string is built before any of
		# it is appended, as at runtime. A conditional over literals is escaped
		# branch by branch.
		private def compile_literal_content(node)
			case node
			in Refract::StringNode | Refract::SymbolNode then plain(node.unescaped)
			in Refract::InterpolatedStringNode if pure?(node) then append(expression(escaped(node)))
			in Refract::NilNode then statements([])
			in Refract::IfNode | Refract::UnlessNode
				folded = fold_conditional(node) { |leaf| literal_content(leaf) }
				append(Output::Conditional.new(folded)) if folded && pure?(folded.predicate)
			else nil
			end
		end

		private def literal_content(node)
			case node
			in Refract::StringNode | Refract::SymbolNode then string(Phlex::Escape.html_escape(node.unescaped))
			in Refract::NilNode then string("")
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
					return Attributes.new(hoisted: [], parts: [literal(Phlex::SGML::Attributes.generate_attributes(static))])
				rescue => e
					# Left to the runtime to raise, in case this code is never reached.
					@diagnostics.report(node, "#{node.name}'s attributes are serialised at runtime because serialising them now raised #{e.class}: #{e.message}")
					return compile_attribute_hash(node.name, keyword_hash, closing)
				end
			end

			compile_attribute_pieces(node, keyword_hash, closing) || compile_attribute_hash(node.name, keyword_hash, closing)
		end

		# Serialises each attribute on its own when every key is a literal. Static
		# values are serialised now, and each dynamic value goes to the helper for
		# its key with the name checks already done. The runtime evaluates every
		# value before serialising any, so every value up to the last impure one
		# is hoisted, and so is every dynamic value when there's more than one,
		# since serialising one could change what another reads.
		private def compile_attribute_pieces(node, keyword_hash, closing)
			normalized_keys = Phlex::SGML::Elements::NORMALIZED_ATTRIBUTES[node.name]
			elements = keyword_hash.elements
			last_impure = elements.rindex { |assoc| !(Refract::AssocNode === assoc) || !pure?(attribute_value(assoc)) }
			several_dynamic = elements.count { |assoc| !(Refract::AssocNode === assoc) || !static_attribute_value(attribute_value(assoc)) } > 1
			keys = Set.new
			hoisted = []

			pieces = catch(:together) do
				elements.each_with_index.map do |assoc, index|
					throw :together, "a key is splatted or isn't a literal" unless assoc in Refract::AssocNode[key: Refract::StringNode | Refract::SymbolNode => key]

					key_value = static_value(key)
					throw :together, "#{key_value} is rewritten by the element's attribute normaliser" if normalized_keys&.include?(key_value)
					throw :together, "#{key_value} is repeated" unless keys.add?(key_value)

					attribute_piece(key, key_value, attribute_value(assoc), hoisted, hoist: several_dynamic || (last_impure && index <= last_impure))
				rescue Phlex::ArgumentError => e
					throw :together, "#{key_value} raised #{e.class}: #{e.message}"
				end
			end

			case pieces
			in String => reason
				@diagnostics.report(node, "#{node.name}'s attributes are serialised together because #{reason}")
				nil
			in Array
				Attributes.new(hoisted:, parts: attribute_parts(pieces.flatten(1), closing))
			end
		end

		# Shorthand `title:` wraps its value in an ImplicitNode, which the
		# formatter prints as nothing when it's taken out of the hash.
		private def attribute_value(assoc)
			(Refract::ImplicitNode === assoc.value) ? assoc.value.value : assoc.value
		end

		# One attribute's parts of the opening tag.
		private def attribute_piece(key, key_value, value, hoisted, hoist:)
			if (static = static_attribute_value(value))
				return [literal(serialized_attribute(key_value, static[0]))]
			end

			name = Phlex::SGML::Attributes.attribute_name(key_value)
			Phlex::SGML::Attributes.validate_attribute_name(key_value, name)

			if (folded = fold_conditional(value) { |leaf| (static = static_attribute_value(leaf)) && string(serialized_attribute(key_value, static[0])) })
				return [hoist ? expression(hoisted_local(folded, hoisted)) : Output::Conditional.new(folded)]
			end

			if (tokens = token_list(key_value, value, hoisted))
				return [Output::Conditional.new(tokens)]
			end

			reference = Phlex::SGML::Attributes.reference_attribute?(name)

			if !reference && (nested = nested_attributes(key_value, name, value, hoisted))
				return nested
			end

			# An interpolation is always a String, so it only needs its quotes
			# escaped. That can raise, as for a string that isn't ASCII-compatible,
			# or on TruffleRuby one that isn't valid, so it's done inside the guard.
			quotable = Refract::InterpolatedStringNode === value
			safe_prefix = reference && quotable && safe_reference_prefix?(value)
			value = hoisted_local(value, hoisted) if hoist || (quotable && !reference) || safe_prefix

			if quotable && !reference
				return [literal(" #{name}=\""), Serialized.new(quoted(value)), literal('"')]
			end

			if safe_prefix
				return [
					Serialized.new(elsif_chain(
						[decodable(value), Refract::InterpolatedStringNode.new(parts: [string(" #{name}=\""), embedded(quoted(value)), string('"')])],
						otherwise: call(constant("Phlex::SGML::Attributes"), :reference_attribute, key, string(name), value)
					)),
				]
			end

			if reference
				return [Serialized.new(call(constant("Phlex::SGML::Attributes"), :reference_attribute, key, string(name), value))]
			end

			value = hoisted_local(value, hoisted) unless hoist
			[Serialized.new(typed_attribute(value, name) { call(constant("Phlex::SGML::Attributes"), :attribute, key, string(name), value) })]
		end

		# Whether an interpolated reference starts with text that rules out a
		# `javascript:` URL, whatever follows it. The runtime decodes character
		# references and keeps only letters and colons before checking, so the
		# text mustn't contain anything decoding could change, and what's left of
		# it must differ from `javascript:` before either ends.
		private def safe_reference_prefix?(node)
			prefix = node.parts.first
			return false unless Refract::StringNode === prefix

			text = prefix.unescaped
			return false unless text.ascii_only? && !text.include?("&") && !text.include?('"')

			normalized = text.downcase.delete("^a-z:")
			!normalized.empty? && !normalized.start_with?("javascript:") && !"javascript:".start_with?(normalized)
		end

		# Whether decoding the string's character references can't raise.
		private def decodable(node)
			Refract::OrNode.new(
				left: call(node, :ascii_only?),
				operator: "||",
				right: Refract::AndNode.new(left: call(constant("Encoding::UTF_8"), :equal?, call(node, :encoding)), operator: "&&", right: call(node, :valid_encoding?))
			)
		end

		# What the serialiser returns, without calling it for true, nil, false or
		# a String, built by appending as the serialiser builds it, since that
		# decides its encoding. The value is read more than once, so it must be a
		# local of the compiler's, which a String's methods can't reassign.
		private def typed_attribute(value, name)
			elsif_chain(
				[call(Refract::TrueNode.new, :equal?, value), string(" #{name}")],
				[call(constant("String"), :===, value), call(call(call(string(" #{name}=\""), :+@), :<<, quoted(value)), :<<, string('"'))],
				[value, yield],
				otherwise: string("")
			)
		end

		# A hash of nested attributes with literal keys, such as `data:`, is
		# serialised entry by entry. Static entries are serialised now, and each
		# dynamic value is evaluated into a local where the hash is, then
		# serialised in order. A `style:` hash is serialised as styles, so it's
		# left to the serialiser.
		private def nested_attributes(key_value, name, value, hoisted)
			return unless Refract::HashNode === value && key_value != :style

			base = "#{name}-"
			return unless value.elements.all? { |assoc| assoc in Refract::AssocNode[key: Refract::StringNode | Refract::SymbolNode] }

			entries = value.elements.map { |assoc| [static_value(assoc.key), assoc.key, attribute_value(assoc)] }
			return unless entries.map(&:first).uniq.length == entries.length

			begin
				entries = entries.map do |(nested_key_value, nested_key, nested_value)|
					nested_name = Phlex::Compiler.nested_attributes(nested_key_value, true, base).delete_prefix(" ")

					if (static = static_attribute_value(nested_value))
						[:static, Phlex::Compiler.nested_attributes(nested_key_value, static[0], base)]
					else
						[:dynamic, nested_key, nested_name, nested_value]
					end
				end
			rescue
				# Left to the serialiser, which skips a key whose value is nil or false.
				return
			end

			entries.map do |entry|
				case entry
				in [:static, text]
					literal(text)
				in [:dynamic, nested_key, nested_name, nested_value]
					nested_value = hoisted_local(nested_value, hoisted)
					Serialized.new(typed_attribute(nested_value, nested_name) { call(constant("Phlex::Compiler"), :nested_attributes, nested_key, nested_value, string(base)) })
				end
			end
		end

		private def elsif_chain(*branches, otherwise:)
			branches.reverse.reduce(Refract::ElseNode.new(statements: statements([otherwise]))) do |subsequent, (predicate, body)|
				Refract::IfNode.new(inline: false, predicate:, statements: statements([body]), subsequent:)
			end
		end

		private def embedded(node)
			Refract::EmbeddedStatementsNode.new(statements: statements([node]))
		end

		# A list of literal tokens, some chosen by conditions, is serialised now
		# for every combination of the conditions. Each condition is tested once,
		# in order, where the runtime evaluates it, and stays in condition
		# position, where some expressions mean something else. Only ASCII text is
		# chosen this way, since appending it can't fail whatever the buffer holds.
		private def token_list(key_value, value, hoisted)
			return unless Refract::ArrayNode === value

			tokens = catch(:dynamic) { value.elements.map { |element| token_choice(element) } }
			choices = tokens&.grep(TokenChoice)
			return unless choices&.length&.between?(1, TOKEN_CONDITIONS_LIMIT)

			texts = token_texts(key_value, tokens, choices.length)
			return unless texts

			conditions = choices.map do |choice|
				hoisted_local(if_node(choice.condition, [Refract::TrueNode.new], else_body: [Refract::FalseNode.new]), hoisted)
			end

			token_tree(conditions, texts)
		end

		# The serialised text for each combination of the conditions.
		private def token_texts(key_value, tokens, conditions)
			texts = [true, false].repeated_permutation(conditions).to_h do |picks|
				pick = picks.each
				chosen = tokens.map { |token| (TokenChoice === token) ? (pick.next ? token.truthy : token.falsy) : token }
				[picks, serialized_attribute(key_value, chosen)]
			end

			texts if texts.each_value.all?(&:ascii_only?)
		rescue
			nil
		end

		private def token_tree(conditions, texts, picks = [])
			return string(texts.fetch(picks)) if picks.length == conditions.length

			if_node(conditions[picks.length], [token_tree(conditions, texts, [*picks, true])], else_body: [token_tree(conditions, texts, [*picks, false])])
		end

		# A literal token, or a condition choosing between two.
		private def token_choice(node)
			case node
			in Refract::ParenthesesNode[body: Refract::StatementsNode[body: [inner]]] then token_choice(inner)
			in Refract::IfNode[subsequent: nil | Refract::ElseNode]
				TokenChoice.new(condition: node.predicate, truthy: branch_token(node.statements), falsy: branch_token(node.subsequent&.statements))
			in Refract::UnlessNode
				TokenChoice.new(condition: node.predicate, truthy: branch_token(node.else_clause&.statements), falsy: branch_token(node.statements))
			else
				token_literal(node)
			end
		end

		private def branch_token(branch)
			case branch
			in nil then nil
			in Refract::StatementsNode[body: [statement]] then token_literal(statement)
			else throw :dynamic
			end
		end

		private def token_literal(node)
			case node
			in Refract::StringNode | Refract::SymbolNode | Refract::IntegerNode | Refract::FloatNode | Refract::NilNode | Refract::FalseNode then static_value(node)
			in Refract::ArrayNode then node.elements.map { |element| token_literal(element) }
			else throw :dynamic
			end
		end

		# The runtime only copies the string if it has quotes to escape.
		private def quoted(node)
			parenthesized([
				if_node(call(node, :include?, string('"')), [call(constant("Phlex::Compiler"), :escape_quotes, node)], else_body: [node]),
			])
		end

		private def hoisted_local(node, hoisted)
			local = @locals.fresh(:value)
			hoisted << write(local, visit(node))
			read(local)
		end

		private def serialized_attribute(key, value)
			Phlex::SGML::Attributes.generate_attributes({ key => value })
		end

		# The runtime builds the whole attribute string before appending any of
		# it, so if a value is invalid the tag closes empty. Serialisations are
		# all evaluated into locals in the first part, and appended after.
		private def attribute_parts(parts, closing)
			writes = []

			parts = parts.map do |part|
				case part
				in Serialized[node]
					local = @locals.fresh(:attribute)
					writes << write(local, node)
					expression(read(local))
				else
					part
				end
			end

			parts[0] = Output::Guarded.new(statements: writes, result: parts[0], closing:) if writes.any?
			parts
		end

		private def compile_attribute_hash(element, keyword_hash, closing)
			hash = case keyword_hash.elements
				in [*, Refract::AssocSplatNode, *] then call(constant("Phlex::Compiler"), :keywords, keyword_hash)
				else Refract::HashNode.new(elements: keyword_hash.elements)
			end
			hoisted = []
			hash = hoisted_local(hash, hoisted)
			attributes = @locals.fresh(:attributes)

			# Element methods only serialise a hash that has something in it.
			serialized = if_node(
				call(call(hash, :length), :>, Refract::IntegerNode.new(value: 0)),
				[*normalize_call(element, hash), cached_attributes(hash)],
				else_body: [string("")]
			)

			Attributes.new(
				hoisted:,
				parts: [
					Output::Guarded.new(
						statements: [write(attributes, serialized)],
						result: expression(read(attributes)),
						closing:
					),
				]
			)
		end

		# As the element method serialises them, through the attribute cache.
		private def cached_attributes(hash)
			call(
				call(read(state_local), :attribute_cache),
				:fetch,
				hash,
				block: Refract::BlockNode.new(parameters: nil, body: statements([call(constant("Phlex::SGML::Attributes"), :generate_attributes, hash)]))
			)
		end

		# Normalizers rewrite the hash in place.
		private def normalize_call(element, hash)
			if (normalizer = attribute_normalizer(element))
				[call(constant("Phlex::SGML::Elements"), normalizer, hash)]
			else
				[]
			end
		end

		private def normalize_attributes(element, attributes)
			if (normalizer = attribute_normalizer(element))
				Phlex::SGML::Elements.public_send(normalizer, attributes)
			end
		end

		private def attribute_normalizer(element)
			Phlex::SGML::Elements::ATTRIBUTE_NORMALIZERS[element]
		end

		private def static_attributes(keyword_hash)
			catch(:dynamic) { static_hash(keyword_hash.elements) }
		end

		# The value wrapped in an array, since a static value can be nil.
		private def static_attribute_value(node)
			catch(:dynamic) { [static_value(node)] }
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
				(Refract::ConstantReadNode === node.receiver && node.receiver.name == :Set && @environment.standard_set?) ||
				(Refract::ConstantPathNode === node.receiver && node.receiver.parent.nil? && node.receiver.name == :Set)
			)
		end

		# Rebuilds a conditional with each literal branch replaced by the block's
		# result, or returns nil if a branch isn't a literal the block handles or
		# a nested condition isn't pure. The outermost condition is left for the
		# caller to check, since the whole conditional can be hoisted. A branch
		# that's missing evaluates to nil, so it gets a nil leaf, which is why a
		# modifier form becomes a block form.
		private def fold_conditional(node, &leaf)
			case node
			in Refract::IfNode | Refract::UnlessNode then catch(:dynamic) { fold(node, &leaf) }
			in Refract::ParenthesesNode[body: Refract::StatementsNode[body: [inner]]] then fold_conditional(inner, &leaf)
			else nil
			end
		end

		private def fold(node, &leaf)
			case node
			in Refract::IfNode
				node.copy(inline: false, statements: fold_branch(node.statements, &leaf), subsequent: fold_else(node.subsequent, &leaf))
			in Refract::UnlessNode
				node.copy(inline: false, statements: fold_branch(node.statements, &leaf), else_clause: fold_else(node.else_clause, &leaf))
			in Refract::ElseNode
				node.copy(statements: fold_branch(node.statements, &leaf))
			in Refract::ParenthesesNode[body: Refract::StatementsNode[body: [inner]]]
				node.copy(body: statements([fold_nested(inner, &leaf)]))
			else
				leaf.call(node) || throw(:dynamic)
			end
		end

		private def fold_nested(node, &leaf)
			throw :dynamic if node in Refract::IfNode | Refract::UnlessNode and !pure?(node.predicate)

			fold(node, &leaf)
		end

		private def fold_branch(branch, &leaf)
			case branch
			in nil then statements([fold(Refract::NilNode.new, &leaf)])
			in Refract::StatementsNode[body: [statement]] then statements([fold_nested(statement, &leaf)])
			else throw :dynamic
			end
		end

		private def fold_else(node, &leaf)
			node ? fold_nested(node, &leaf) : Refract::ElseNode.new(statements: fold_branch(nil, &leaf))
		end

		# Whether evaluating the node can't have side effects or raise, so it's
		# safe to evaluate it inside an append that may be skipped. Constants are
		# excluded: reading one can autoload or raise NameError. So are
		# interpolations and splats, which call to_s and to_hash, and hash keys
		# that could have a `hash` method of their own. Conditionals over pure
		# operands are pure, since they only choose between them.
		private def pure?(node)
			case node
			in nil | Refract::StringNode | Refract::SymbolNode | Refract::IntegerNode | Refract::FloatNode |
				Refract::RationalNode | Refract::ImaginaryNode | Refract::RegularExpressionNode |
				Refract::TrueNode | Refract::FalseNode | Refract::NilNode | Refract::SelfNode |
				Refract::LocalVariableReadNode | Refract::InstanceVariableReadNode | Refract::EmbeddedVariableNode
				true
			in Refract::ArrayNode | Refract::HashNode | Refract::KeywordHashNode then node.elements.all? { |element| pure?(element) }
			in Refract::AssocNode[key: Refract::StringNode | Refract::SymbolNode | Refract::IntegerNode | Refract::FloatNode | Refract::NilNode | Refract::TrueNode | Refract::FalseNode] then pure?(node.value)
			in Refract::InterpolatedStringNode then node.parts.all? { |part| Refract::StringNode === part }
			in Refract::ParenthesesNode then pure?(node.body)
			in Refract::StatementsNode then node.body.all? { |statement| pure?(statement) }
			in Refract::IfNode then pure?(node.predicate) && pure?(node.statements) && pure?(node.subsequent)
			in Refract::UnlessNode then pure?(node.predicate) && pure?(node.statements) && pure?(node.else_clause)
			in Refract::ElseNode then pure?(node.statements)
			in Refract::AndNode | Refract::OrNode then pure?(node.left) && pure?(node.right)
			else false
			end
		end

		# An interpolation is built, calling to_s on its parts, before the runtime
		# checks whether it's rendering, so it's evaluated into a local first.
		private def compile_plain(node)
			# Keep runtime block rejection and evaluation of forwarded block expressions.
			return keep_call(node, "it has a block") if node.block

			case node.arguments&.arguments
			in [Refract::StringNode | Refract::SymbolNode => text] then plain(text.unescaped)
			in [Refract::InterpolatedStringNode => interpolated]
				text = @locals.fresh(:text)
				statements([write(text, visit(interpolated)), append(expression(escaped(read(text))))])
			in [Refract::NilNode] then Refract::NilNode.new
			else keep_call(node, "its argument isn't a literal or an interpolation")
			end
		end

		# `raw safe("…")` is a literal that skips escaping.
		private def compile_raw(node)
			# Keep evaluation of forwarded block expressions, which may raise.
			return keep_call(node, "it has a block") if node.block

			case node.arguments&.arguments
			in [Refract::CallNode[receiver: nil, name: :safe, block: nil, arguments: Refract::ArgumentsNode[arguments: [Refract::StringNode => text]]]] if @environment.helper?(:safe)
				@environment.inlined << :safe
				raw(text.unescaped)
			else
				keep_call(node, "its argument isn't safe with a string literal")
			end
		end

		private def compile_whitespace(node)
			return keep_call(node, "it has arguments") if node.arguments
			return raw(" ") if node.block.nil?

			compile_wrapped_content(node, " ", " ")
		end

		private def compile_comment(node)
			return keep_call(node, "it has arguments") if node.arguments

			compile_wrapped_content(node, "<!-- ", " -->")
		end

		# Unlike an element, the runtime has no `ensure`, so a jump out of the
		# block skips the closing text, and only a block that can be inlined is
		# compiled. A forwarded block, which may be nil, keeps the runtime call too.
		private def compile_wrapped_content(node, opening, closing)
			return compile_call_with_content(node, because: "its block is forwarded or #{UNINLINABLE_BLOCK}") unless inlinable_content?(node.block)

			statements([raw(opening), *compile_content(node), raw(closing)])
		end

		private def inlinable_content?(block)
			case block
			in nil then true
			in Refract::BlockNode then block.body.nil? || inlinable?(block)
			else false
			end
		end

		private def compile_doctype(node)
			return keep_call(node, "it has arguments or a block") if node.arguments || node.block

			raw("<!doctype html>")
		end

		# A fragment always keeps its call, since it drives the render check, but
		# the content is still compiled.
		private def compile_fragment(node)
			return keep_call(node, "its block has parameters or is forwarded") unless node.block in Refract::BlockNode[parameters: nil]

			compile_call_with_content(node)
		end

		private def keep_call(node, because)
			@diagnostics.report(node, "#{node.name} keeps its call because #{because}")
			nil
		end

		private def escaped(node)
			call(constant("Phlex::Escape"), :html_escape, node)
		end

		private def plain(text)
			raw(Phlex::Escape.html_escape(text))
		end

		private def raw(text)
			append(literal(text))
		end

		private def literal(text)
			text => String

			Output::Literal.new(text)
		end

		private def expression(node)
			Output::Expression.new(node)
		end

		private def append(*parts)
			@appends += 1
			state_local

			Output::Append.new(parts:)
		end

		private def opening(buffer, *parts)
			@appends += 1
			state_local

			Output::Opening.new(parts:, buffer:)
		end

		# Guarded blocks read the state themselves, so only output outside them
		# needs it read on entry.
		private def state_local
			unless @state_local_set || @guarded_blocks > 0
				@preamble << write(Locals::STATE, Refract::InstanceVariableReadNode.new(name: :@_state))
				@state_local_set = true
			end

			Locals::STATE
		end

		private def self_local
			unless @self_local_set
				@preamble << write(Locals::SELF, Refract::SelfNode.new)
				@self_local_set = true
			end

			Locals::SELF
		end
	end
end
