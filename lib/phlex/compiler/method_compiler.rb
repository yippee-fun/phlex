# frozen_string_literal: true

module Phlex::Compiler
	# Rewrites one method so that the element and helper calls it makes become
	# output nodes in its tree, which the Emitter then lowers to buffer appends.
	class MethodCompiler < Refract::MutationVisitor
		include Builder

		Attributes = Data.define(:hoisted, :parts)
		NO_ATTRIBUTES = Attributes.new(hoisted: [], parts: [])

		# One attribute's contribution to the opening tag, and whether
		# evaluating it runs the serialiser, which can raise.
		Piece = Data.define(:parts, :raises)

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

			if (reserved = LocalsScanner.names(node).find { |name| name.start_with?("__phlex_") })
				@diagnostics.refuse(node, "#{reserved} is a local the compiler reserves; names starting with __phlex_ can't be used")
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
		# read on entry, and maps its own exceptions, as the method's rescue may
		# no longer be on the stack.
		visit Refract::BlockNode do |node|
			return super(node) unless @compiling_calls && node.body

			if @guarded_blocks == GUARDED_BLOCK_DEPTH_LIMIT
				@diagnostics.report(node, "calls in this block are left to the runtime because it's nested #{GUARDED_BLOCK_DEPTH_LIMIT} blocks deep")
				return without_compiling_calls { super(node) }
			end

			appends = @appends
			@guarded_blocks += 1
			compiled = visit(node.body)
			@guarded_blocks -= 1
			return node if appends == @appends

			original = without_compiling_calls { visit(node.body) }

			node.copy(
				body: statements([
					if_node(
						call(Refract::SelfNode.new, :equal?, read(self_local)),
						[mapping_exceptions([write(Locals::STATE, Refract::InstanceVariableReadNode.new(name: :@_state)), compiled])],
						else_body: [original]
					),
				])
			)
		end

		private def mapping_exceptions(body)
			begin_node(
				body,
				rescue_clause: rescue_node(
					[constant("Exception")],
					Refract::LocalVariableTargetNode.new(name: Locals::EXCEPTION),
					[call(constant("Kernel"), :raise, call(nil, :__map_exception__, read(Locals::EXCEPTION)))]
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

		# A forwarded block is evaluated before the element opens and may be nil,
		# so it keeps the runtime call. The runtime closes the element however
		# its content exits, which the enclosure reproduces.
		private def compile_standard_element(node, tag)
			return compile_call_with_content(node, because: "its block is forwarded") if Refract::BlockArgumentNode === node.block

			attributes = compile_attributes(node, node.block ? ">" : "></#{tag}>")
			return compile_call_with_content(node, because: "it has positional arguments") unless attributes

			statements([
				*attributes.hoisted,
				append(literal("<#{tag}"), *attributes.parts, literal(">")),
				Output::Enclosed.new(body: compile_content(node), closing: "</#{tag}>"),
				raw("</#{tag}>"),
				*(flush_after_head if tag == "head"),
			])
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

		private def compile_content(node)
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
				known = @environment.element(node.name) || (@environment.helper?(node.name) && node.name in :plain | :whitespace | :doctype | :comment | :fragment | :raw)
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
				Attributes.new(hoisted:, parts: attribute_parts(pieces, closing))
			end
		end

		# Shorthand `title:` wraps its value in an ImplicitNode, which the
		# formatter prints as nothing when it's taken out of the hash.
		private def attribute_value(assoc)
			(Refract::ImplicitNode === assoc.value) ? assoc.value.value : assoc.value
		end

		private def attribute_piece(key, key_value, value, hoisted, hoist:)
			if (static = static_attribute_value(value))
				return Piece.new(parts: [literal(serialized_attribute(key_value, static[0]))], raises: false)
			end

			name = Phlex::SGML::Attributes.attribute_name(key_value)
			Phlex::SGML::Attributes.validate_attribute_name(key_value, name)

			if (folded = fold_conditional(value) { |leaf| (static = static_attribute_value(leaf)) && string(serialized_attribute(key_value, static[0])) })
				part = hoist ? expression(hoisted_local(folded, hoisted)) : Output::Conditional.new(folded)
				return Piece.new(parts: [part], raises: false)
			end

			interpolated = Refract::InterpolatedStringNode === value
			reference = Phlex::SGML::Attributes.reference_attribute?(name)
			value = hoisted_local(value, hoisted) if hoist

			if interpolated && !reference
				return Piece.new(parts: [literal(" #{name}=\""), expression(quoted(value)), literal('"')], raises: false)
			end

			serializer = reference ? :reference_attribute : :attribute
			Piece.new(parts: [expression(call(constant("Phlex::SGML::Attributes"), serializer, key, string(name), value))], raises: true)
		end

		# An interpolation is always a String, so it only needs its quotes escaped.
		private def quoted(node)
			call(node, :gsub, string('"'), string("&quot;"))
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
		# it, so if a value is invalid the tag closes empty. Pieces that can raise
		# are all evaluated into locals in the first part, and appended after.
		private def attribute_parts(pieces, closing)
			raising = pieces.select(&:raises)
			return pieces.flat_map(&:parts) if raising.empty?

			locals = raising.to_h { |piece| [piece, @locals.fresh(:attribute)] }
			writes = raising.map { |piece| write(locals[piece], piece.parts.first.node) }
			parts = pieces.flat_map { |piece| locals.key?(piece) ? [expression(read(locals[piece]))] : piece.parts }
			parts[0] = Output::Guarded.new(statements: writes, result: parts[0], closing:)
			parts
		end

		private def compile_attribute_hash(element, keyword_hash, closing)
			hash = Refract::HashNode.new(elements: keyword_hash.elements)
			hoisted = []
			hash = hoisted_local(hash, hoisted) unless pure?(hash)
			attributes = @locals.fresh(:attributes)

			Attributes.new(
				hoisted:,
				parts: [
					Output::Guarded.new(
						statements: [write(attributes, attributes_call(element, hash))],
						result: expression(read(attributes)),
						closing:
					),
				]
			)
		end

		private def attributes_call(element, hash)
			if (normalizer = attribute_normalizer(element))
				hash = call(constant("Phlex::SGML::Elements"), normalizer, hash)
			end

			call(nil, :__attributes__, hash)
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
		# interpolations and splats, which call to_s and to_hash. Conditionals
		# over pure operands are pure, since they only choose between them.
		private def pure?(node)
			case node
			in nil | Refract::StringNode | Refract::SymbolNode | Refract::IntegerNode | Refract::FloatNode |
				Refract::RationalNode | Refract::ImaginaryNode | Refract::RegularExpressionNode |
				Refract::TrueNode | Refract::FalseNode | Refract::NilNode | Refract::SelfNode |
				Refract::LocalVariableReadNode | Refract::InstanceVariableReadNode | Refract::EmbeddedVariableNode
				true
			in Refract::ArrayNode | Refract::HashNode | Refract::KeywordHashNode then node.elements.all? { |element| pure?(element) }
			in Refract::AssocNode then pure?(node.key) && pure?(node.value)
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

		# Unlike an element, the runtime doesn't yield the block at all when the
		# output is being skipped, so dynamic content needs the same guard. And
		# with no `ensure`, a jump out of the block skips the closing text, so
		# only a block that can be inlined is compiled. A forwarded block, which
		# may be nil, keeps the runtime call too.
		private def compile_wrapped_content(node, opening, closing)
			return compile_call_with_content(node, because: "its block is forwarded or #{UNINLINABLE_BLOCK}") unless inlinable_content?(node.block)

			content = compile_content(node)
			body = [raw(opening), *content, raw(closing)]
			return statements(body) if Output.static?(content)

			if_node(should_render, body)
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
