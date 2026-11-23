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
	SIMPLE_ATTRIBUTE_NAME = /\A[a-z-]+\z/

	# Symbol keys whose names have passed every name check, mapped to their names.
	# Values for these only need serialising. Reference attributes are kept apart
	# because their values also need checking. Replaced rather than mutated, so
	# they stay shareable between Ractors.
	@checked_names = {}.freeze
	@checked_reference_names = {}.freeze
	@checked_names_mutex = Mutex.new
	CHECKED_NAMES_LIMIT = 1_000

	def generate_attributes(attributes, buffer = +"")
		checked_names = @checked_names
		checked_reference_names = @checked_reference_names

		attributes.each do |k, v|
			next unless v

			if (name = checked_names[k])
				case v
				when String
					buffer << " " << name << '="' << ((v.include?('"') || v.include?("<") || v.include?(">")) ? v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : v) << '"'
				when true
					buffer << " " << name
				else
					generate_attribute(k, name, v, buffer)
				end
			elsif String === v && (name = checked_reference_names[k]) && !(Phlex::SGML::SafeObject === v)
				value = (v.include?('"') || v.include?("<") || v.include?(">")) ? v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : v
				buffer << " " << name << '="' << value << '"' unless unsafe_reference?(value)
			else
				generate_attribute(k, attribute_name(k), v, buffer)
			end
		end

		buffer
	end

	def attribute_name(k)
		case k
		when String then k
		when Symbol then (n = k.name).include?("_") ? n.tr("_", "-") : n
		else raise Phlex::ArgumentError.new("Attribute keys should be Strings or Symbols.")
		end
	end

	# Serialises one attribute into the buffer, with every check.
	def generate_attribute(k, name, v, buffer)
		value = attribute_value(k, name, v, buffer)

		if (simple_name = name.match?(SIMPLE_ATTRIBUTE_NAME))
			# Fast path: the name is already lowercase and contains only `a-z` and `-`,
			# so normalising it would be a no-op and it can't contain unsafe characters.
			lower_name = normalized_name = name
		else
			lower_name = name.downcase
			normalized_name = lower_name.delete("^a-z-")
		end

		# Only Phlex's own `safe` can use an unsafe name or a script URL. Other safe
		# objects, such as Rails' html_safe strings, are safe as HTML, not as script.
		if Phlex::SGML::SafeValue === v
			check_attribute_name(k, name, lower_name, simple_name)
		else
			reference_name = simple_name ? normalized_name : local_name(lower_name)

			if !true.equal?(value) && (REF_ATTRIBUTES.include?(reference_name) || DATA_ATTRIBUTE == reference_name) && drop_reference?(k, v, value, reference_name)
				# We just ignore these because they were likely not specified by the developer.
				return buffer
			end

			check_unsafe_attribute_name(k, normalized_name)
			check_attribute_name(k, name, lower_name, simple_name)
			remember_checked_name(k, name) if simple_name && Symbol === k
		end

		append_attribute(buffer, name, value)
	end

	private def remember_checked_name(k, name)
		# Lists are checked entry by entry, which the remembered path doesn't do.
		return if REF_LIST_ATTRIBUTES.include?(name)

		reference = REF_ATTRIBUTES.include?(name) || DATA_ATTRIBUTE == name
		names = reference ? @checked_reference_names : @checked_names
		return if names.key?(k) || names.size >= CHECKED_NAMES_LIMIT || !Phlex.__main_ractor__?

		@checked_names_mutex.synchronize do
			names = reference ? @checked_reference_names : @checked_names
			next if names.key?(k) || names.size >= CHECKED_NAMES_LIMIT

			names = names.merge(k => -name)
			names = defined?(::Ractor) ? ::Ractor.make_shareable(names) : names.freeze

			if reference
				@checked_reference_names = names
			else
				@checked_names = names
			end
		end
	end

	# Raises if the name fails a check that doesn't depend on the value, so a
	# name that passes can be serialised with `attribute` or `reference_attribute`.
	def validate_attribute_name(k, name)
		lower_name = name.downcase
		check_unsafe_attribute_name(k, lower_name.delete("^a-z-"))
		check_attribute_name(k, name, lower_name, false)
	end

	def reference_attribute?(name)
		REF_ATTRIBUTES.include?(local_name(name.downcase))
	end

	# Whether the attribute is `data`, a reference unless its value is a Hash
	# that expands into `data-*` attributes.
	def data_attribute?(name)
		DATA_ATTRIBUTE == local_name(name.downcase)
	end

	# Whether the attribute's value is a `;`-separated list of references.
	def reference_list_attribute?(name)
		REF_LIST_ATTRIBUTES.include?(local_name(name.downcase))
	end

	# The normalised name without any namespace prefix. In an SVG document parsed
	# as XML, any prefix can be bound to XLink, so `x:href` can be a reference.
	def local_name(lower_name)
		(index = lower_name.rindex(":")) ? lower_name[(index + 1)..].delete("^a-z-") : lower_name.delete("^a-z-")
	end

	# The text to append for an attribute whose name has been validated.
	def attribute(k, name, v)
		return "" unless v

		buffer = +""
		append_attribute(buffer, name, attribute_value(k, name, v, buffer))
	end

	# The text to append for a validated attribute that references a URL.
	def reference_attribute(k, name, v)
		return "" unless v

		buffer = +""
		value = attribute_value(k, name, v, buffer)

		if !true.equal?(value) && !(Phlex::SGML::SafeValue === v) && drop_reference?(k, v, value, local_name(name.downcase))
			return ""
		end

		append_attribute(buffer, name, value)
	end

	private def attribute_value(k, name, v, buffer)
		case v
		when true
			true
		when String
			(v.include?('"') || v.include?("<") || v.include?(">")) ? v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : v
		when Symbol
			n = v.name
			n = n.tr("_", "-") if n.include?("_")
			(n.include?('"') || n.include?("<") || n.include?(">")) ? n.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : n
		when Integer, Float
			v.to_s
		when Date, Time
			date_time_value(v)
		when Hash
			case k
			when :style
				generate_styles(v)&.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			else
				generate_nested_attributes(v, "#{name}-", buffer)
			end
		when Array
			case k
			when :style
				generate_styles(v)&.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			else
				generate_nested_tokens(v)
			end
		when Set
			case k
			when :style
				generate_styles(v)&.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
			else
				generate_nested_tokens(v.to_a)
			end
		when Phlex::SGML::SafeObject
			v.to_s.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
		else
			if v.respond_to?(:to_h)
				case k
				when :style
					generate_styles(v.to_h)&.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES)
				else
					generate_nested_attributes(v.to_h, "#{name}-", buffer)
				end
			else
				raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
			end
		end
	end

	# Dates serialise as `YYYY-MM-DD` and Times as ISO 8601, which is what the
	# `datetime` attribute and most `data-` consumers expect.
	private def date_time_value(v)
		if Time === v && !v.respond_to?(:iso8601)
			v.strftime("%Y-%m-%dT%H:%M:%S%:z")
		else
			v.iso8601
		end
	end

	# Whether a reference should be dropped because it could run script. Only a
	# String can be a reference.
	private def drop_reference?(k, v, value, normalized_name)
		case value
		when String
			REF_LIST_ATTRIBUTES.include?(normalized_name) ? unsafe_reference_list?(value) : unsafe_reference?(value)
		else
			# A `data` Hash has already expanded into `data-*` attributes.
			return false if DATA_ATTRIBUTE == normalized_name

			raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
		end
	end

	private def check_unsafe_attribute_name(k, normalized_name)
		if normalized_name.bytesize > 2 && normalized_name.start_with?("on") && !normalized_name.include?("-")
			raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
		end

		if UNSAFE_ATTRIBUTES.include?(normalized_name)
			raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
		end
	end

	private def check_attribute_name(k, name, lower_name, simple_name)
		if !simple_name && name.match?(UNSAFE_ATTRIBUTE_NAME_CHARS)
			raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
		end

		if name.empty?
			raise Phlex::ArgumentError.new("Attribute names can't be empty.")
		end

		if lower_name == "id" && k != :id
			raise Phlex::ArgumentError.new(":id attribute should only be passed as a lowercase symbol.")
		end
	end

	private def append_attribute(buffer, name, value)
		case value
		when true
			buffer << " " << name
		when String
			buffer << " " << name << '="' << value << '"'
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
					when Symbol then (n = k.name).include?("_") ? n.tr("_", "-") : n
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
				buffer << " " << checked_nested_name(base_name, name) << '="' << ((v.include?('"') || v.include?("<") || v.include?(">")) ? v.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : v) << '"'
			when Symbol
				n = v.name
				n = n.tr("_", "-") if n.include?("_")
				buffer << " " << checked_nested_name(base_name, name) << '="' << ((n.include?('"') || n.include?("<") || n.include?(">")) ? n.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : n) << '"'
			when Integer, Float
				buffer << " " << checked_nested_name(base_name, name) << '="' << v.to_s << '"'
			when Date, Time
				buffer << " " << checked_nested_name(base_name, name) << '="' << date_time_value(v) << '"'
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
				# Like a nested Hash, an object that converts to one expands into
				# further nested attributes, matching the top-level behaviour.
				if v.respond_to?(:to_h)
					generate_nested_attributes(v.to_h, "#{base_name}#{name}-", buffer)
				else
					raise Phlex::ArgumentError.new("Invalid attribute value #{v.inspect}.")
				end
			end

			if root_key
				base_name = original_base_name
			end

			buffer
		end
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
	# references, whitespace or case. The full check has to decode and normalise
	# the value, which allocates several strings, so it's skipped when the value
	# can't possibly normalise to `javascript:`. Character references are the only
	# way to introduce a `j` or a `:` that isn't already present in the value,
	# and without an `&` there's nothing to decode.
	def unsafe_reference?(value)
		if value.include?("&")
			decode_html_character_references(value).downcase.delete("^a-z:").start_with?("javascript:")
		elsif value.include?(":") && (value.include?("j") || value.include?("J"))
			# A subclass could override `downcase`; decoding returned a plain String.
			(String.equal?(value.class) ? value : String.new(value)).downcase.delete("^a-z:").start_with?("javascript:")
		else
			false
		end
	end

	# Like `unsafe_reference?`, for a `;`-separated list such as `values`, where
	# any entry can be used. The decoder removes references it doesn't know,
	# but a browser keeps them as text, so it could see a `;` the decoder
	# removed. Removing text can't break up an entry's `javascript:`, so the
	# list is unsafe if `javascript:` appears anywhere in it.
	def unsafe_reference_list?(value)
		if value.include?("&")
			decode_html_character_references(value).downcase.delete("^a-z:").include?("javascript:")
		elsif value.include?(":") && (value.include?("j") || value.include?("J"))
			# A subclass could override `downcase`; decoding returned a plain String.
			(String.equal?(value.class) ? value : String.new(value)).downcase.delete("^a-z:").include?("javascript:")
		else
			false
		end
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
		in 0xD800..0xDFFF | 0x110000.. then "�"
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
				token = token.name
				token = token.tr("_", "-") if token.include?("_")
				if buffer.empty?
					buffer << token
				else
					buffer << sep << token
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
			when nil, false
				# Do nothing
			else
				raise Phlex::ArgumentError.new("Invalid token type: #{token.class}.")
			end

			i += 1
		end

		return if buffer.empty?

		(buffer.include?('"') || buffer.include?("<") || buffer.include?(">")) ? buffer.gsub(UNSAFE_VALUE_CHARS, VALUE_ESCAPES) : buffer
	end

	# The result is unsafe so should be escaped.
	def generate_styles(styles)
		case styles
		when Array, Set
			styles = styles.filter_map do |s|
				case s
				when String
					if s == ""
						next nil
					elsif s.end_with?(";")
						s
					else
						"#{s};"
					end
				when Phlex::SGML::SafeObject
					value = s.to_s
					value.end_with?(";") ? value : "#{value};"
				when Hash
					next generate_styles(s)
				when nil, false
					next nil
				else
					raise Phlex::ArgumentError.new("Invalid style: #{s.inspect}.")
				end
			end

			styles.join(" ") unless styles.empty?
		when Hash
			buffer = +""
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
				when nil, false
					nil
				else
					raise Phlex::ArgumentError.new("Invalid style value: #{v.inspect}")
				end

				if value
					buffer << " " unless buffer.empty?
					buffer << prop << ": " << value << ";"
				end
			end

			buffer unless buffer.empty?
		end
	end
end

Phlex::SGML::Attributes.singleton_class.prepend(Phlex::Native::Attributes) if defined?(Phlex::Native)
