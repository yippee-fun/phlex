# frozen_string_literal: true

module Phlex::SGML::Attributes
	extend self

	UNSAFE_ATTRIBUTES = Set.new(%w[srcdoc sandbox http-equiv]).freeze
	# SVG animation elements, such as `set` and `animate`, write `to`, `from`,
	# `by` and `values` to the attribute their `attributeName` names, which can
	# be `href`, so those are checked as references too.
	REF_ATTRIBUTES = Set.new(%w[href src action formaction lowsrc dynsrc background ping xlinkhref to from by values]).freeze
	# References whose value is a `;`-separated list, any entry of which can be used.
	REF_LIST_ATTRIBUTES = Set.new(%w[values]).freeze
	# `data` takes a URL on `object`, but a Hash given to it expands into `data-*`
	# attributes, so it's checked as a reference only when its value doesn't expand.
	DATA_ATTRIBUTE = "data"
	NAMED_CHARACTER_REFERENCES = {
		"colon" => ":",
		"tab" => "\t",
		"newline" => "\n",
		"semi" => ";",
	}.freeze
	UNSAFE_ATTRIBUTE_NAME_CHARS = %r([<>&"'/=\s\x00])
	# Escaped in attribute values. `"` would end the value, and `<` or `>` could
	# end an element whose content isn't parsed as markup, such as `</noscript>`,
	# or a comment, with `-->`. Escaping them doesn't change the value the browser reads.
	UNSAFE_VALUE_CHARS = /["<>]/
	VALUE_ESCAPES = { '"' => "&quot;", "<" => "&lt;", ">" => "&gt;" }.freeze

	def generate_attributes(attributes, buffer = +"")
		attributes.each do |k, v|
			next unless v

			name = case k
				when String then k
				when Symbol then k.name.tr("_", "-")
				else raise Phlex::ArgumentError.new("Attribute keys should be Strings or Symbols.")
			end

			value = case v
			when true
				true
			when String
				v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			when Symbol
				v.name.tr("_", "-").gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			when Integer, Float
				v.to_s
			when Date
				v.iso8601
			when Time
				v.respond_to?(:iso8601) ? v.iso8601 : v.strftime("%Y-%m-%dT%H:%M:%S%:z")
			when Hash
				case k
				when :style
					generate_styles(v).gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
				else
					generate_nested_attributes(v, "#{name}-", buffer)
				end
			when Array
				case k
				when :style
					generate_styles(v).gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
				else
					generate_nested_tokens(v)
				end
			when Set
				case k
				when :style
					generate_styles(v).gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
				else
					generate_nested_tokens(v.to_a)
				end
			when Phlex::SGML::SafeObject
				v.to_s.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			else
				if v.respond_to?(:to_h)
					case k
					when :style
						generate_styles(v.to_h).gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
					else
						generate_nested_attributes(v.to_h, "#{name}-", buffer)
					end
				else
					raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
				end
			end

			lower_name = name.downcase

			# Only Phlex's own `safe` can use an unsafe name or a script URL. Other safe
			# objects, such as Rails' html_safe strings, are safe as HTML, not as script.
			unless Phlex::SGML::SafeValue === v
				normalized_name = lower_name.delete("^a-z-")

				# In an SVG document parsed as XML, any prefix can be bound to XLink,
				# so whether a name is a reference depends on its local name.
				reference_name = local_name(lower_name)

				if value != true && (REF_ATTRIBUTES.include?(reference_name) || DATA_ATTRIBUTE == reference_name)
					case value
					when String
						unsafe = REF_LIST_ATTRIBUTES.include?(reference_name) ? unsafe_reference_list?(value) : unsafe_reference?(value)

						if unsafe
							# We just ignore these because they were likely not specified by the developer.
							next
						end
					else
						# A `data` Hash has already expanded into `data-*` attributes.
						unless DATA_ATTRIBUTE == reference_name
							raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
						end
					end
				end

				if normalized_name.bytesize > 2 && normalized_name.start_with?("on") && !normalized_name.include?("-")
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end

				if UNSAFE_ATTRIBUTES.include?(normalized_name)
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end
			end

			if name.match?(UNSAFE_ATTRIBUTE_NAME_CHARS)
				raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
			end

			if lower_name.to_sym == :id && k != :id
				raise Phlex::ArgumentError.new(":id attribute should only be passed as a lowercase symbol.")
			end

			case value
			when true
				buffer << " " << name
			when String
				buffer << " " << name << '="' << value << '"'
			end
		end

		buffer
	end

	# Provides the nested-attributes case for serializing out attributes.
	# This allows us to skip many of the checks the `__attributes__` method must perform.
	def generate_nested_attributes(attributes, base_name, buffer = +"")
		attributes.each do |k, v|
			next unless v

			if (root_key = (:_ == k))
				name = ""
				original_base_name = base_name
				base_name = base_name.delete_suffix("-")
			else
				name = case k
					when String then k
					when Symbol then k.name.tr("_", "-")
					else raise Phlex::ArgumentError.new("Attribute keys should be Strings or Symbols")
				end

				if name.match?(UNSAFE_ATTRIBUTE_NAME_CHARS)
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end
			end

			case v
			when true
				buffer << " " << checked_nested_name(base_name, name)
			when String
				buffer << " " << checked_nested_name(base_name, name) << '="' << v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) << '"'
			when Symbol
				buffer << " " << checked_nested_name(base_name, name) << '="' << v.name.tr("_", "-").gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) << '"'
			when Integer, Float
				buffer << " " << checked_nested_name(base_name, name) << '="' << v.to_s << '"'
			when Hash
				generate_nested_attributes(v, "#{base_name}#{name}-", buffer)
			when Array
				if (value = generate_nested_tokens(v))
					buffer << " " << checked_nested_name(base_name, name) << '="' << value << '"'
				end
			when Set
				if (value = generate_nested_tokens(v.to_a))
					buffer << " " << checked_nested_name(base_name, name) << '="' << value << '"'
				end
			when Phlex::SGML::SafeObject
				nested_name = (Phlex::SGML::SafeValue === v) ? "#{base_name}#{name}" : checked_nested_name(base_name, name)
				buffer << " " << nested_name << '="' << v.to_s.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) << '"'
			else
				raise Phlex::ArgumentError.new("Invalid attribute value #{v.inspect}.")
			end

			if root_key
				base_name = original_base_name
			end

			buffer
		end
	end

	# The normalised name without any namespace prefix.
	def local_name(lower_name)
		(index = lower_name.rindex(":")) ? lower_name[(index + 1)..].delete("^a-z-") : lower_name.delete("^a-z-")
	end

	# Joined to its base, a nested name can spell an unsafe one, such as `http-equiv`.
	private def checked_nested_name(base_name, name)
		full_name = "#{base_name}#{name}"

		if UNSAFE_ATTRIBUTES.include?(full_name.downcase.delete("^a-z-"))
			raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{full_name}.")
		end

		# Nested values aren't checked as references, so a nested name can't be one,
		# as `x: { "a:href" => }` would be with its prefix bound to XLink.
		if full_name.include?(":") && REF_ATTRIBUTES.include?(local_name(full_name.downcase))
			raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{full_name}.")
		end

		full_name
	end

	# Detects `javascript:` URLs, including ones obfuscated with HTML character
	# references, whitespace or case.
	def unsafe_reference?(value)
		decode_html_character_references(value).downcase.delete("^a-z:").start_with?("javascript:")
	end

	# Like `unsafe_reference?`, for a `;`-separated list such as `values`, where
	# any entry can be used. The decoder removes references it doesn't know,
	# but a browser keeps them as text, so it could see a `;` the decoder
	# removed. Removing text can't break up an entry's `javascript:`, so the
	# list is unsafe if `javascript:` appears anywhere in it.
	def unsafe_reference_list?(value)
		decode_html_character_references(value).downcase.delete("^a-z:").include?("javascript:")
	end

	def decode_html_character_references(value)
		value
			.gsub(/&#x([0-9a-f]+);?/i) { numeric_character_reference($1, 16, 6) }
			.gsub(/&#(\d+);?/) { numeric_character_reference($1, 10, 7) }
			.gsub(/&([a-z][a-z0-9]+);?/i) {
				NAMED_CHARACTER_REFERENCES[$1.downcase] || ""
			}
	end

	# Digits past what U+10FFFF needs, once leading zeros are dropped, can only
	# be past Unicode, so they're decoded as U+FFFD without parsing them.
	private def numeric_character_reference(digits, base, max_length)
		digits = digits.sub(/\A0+(?=.)/, "")
		(digits.length > max_length) ? "\uFFFD" : character_reference(digits.to_i(base))
	end

	# Browsers decode surrogates and code points past Unicode as U+FFFD.
	private def character_reference(code_point)
		case code_point
		in 0xD800..0xDFFF | 0x110000.. then "\uFFFD"
		else code_point.chr(Encoding::UTF_8)
		end
	end

	def generate_nested_tokens(tokens, sep = " ", gsub_from = nil, gsub_to	= "")
		buffer = +""

		i, length = 0, tokens.length

		while i < length
			token = tokens[i]

			case token
			when String
				token = token.gsub(gsub_from, gsub_to) if gsub_from
				if buffer.empty?
					buffer << token
				else
					buffer << sep << token
				end
			when Symbol
				if buffer.empty?
					buffer << token.name.tr("_", "-")
				else
					buffer << sep << token.name.tr("_", "-")
				end
			when Integer, Float, Phlex::SGML::SafeObject
				if buffer.empty?
					buffer << token.to_s
				else
					buffer << sep << token.to_s
				end
			when Array
				if token.length > 0 && (value = generate_nested_tokens(token, sep, gsub_from, gsub_to))
					if buffer.empty?
						buffer << value
					else
						buffer << sep << value
					end
				end
			when Set
				if token.length > 0 && (value = generate_nested_tokens(token.to_a, sep, gsub_from, gsub_to))
					if buffer.empty?
						buffer << value
					else
						buffer << sep << value
					end
				end
			when nil
				# Do nothing
			else
				raise Phlex::ArgumentError.new("Invalid token type: #{token.class}.")
			end

			i += 1
		end

		return if buffer.empty?

		buffer.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
	end

	# The result is unsafe so should be escaped.
	def generate_styles(styles)
		case styles
		when Array, Set
			styles.filter_map do |s|
				case s
				when String
					if s == "" || s.end_with?(";")
						s
					else
						"#{s};"
					end
				when Phlex::SGML::SafeObject
					value = s.to_s
					value.end_with?(";") ? value : "#{value};"
				when Hash
					next generate_styles(s)
				when nil
					next nil
				else
					raise Phlex::ArgumentError.new("Invalid style: #{s.inspect}.")
				end
			end.join(" ")
		when Hash
			buffer = +""
			i = 0
			styles.each do |k, v|
				prop = case k
				when String
					k
				when Symbol
					k.name.tr("_", "-")
				else
					raise Phlex::ArgumentError.new("Style keys should be Strings or Symbols.")
				end

				value = case v
				when String
					v
				when Symbol
					v.name.tr("_", "-")
				when Integer, Float, Phlex::SGML::SafeObject
					v.to_s
				when nil
					nil
				else
					raise Phlex::ArgumentError.new("Invalid style value: #{v.inspect}")
				end

				if value
					if i == 0
						buffer << prop << ": " << value << ";"
					else
						buffer << " " << prop << ": " << value << ";"
					end
				end

				i += 1
			end

			buffer
		end
	end
end
