# frozen_string_literal: true

module Phlex::SGML::Attributes
	extend self

	UNSAFE_ATTRIBUTES = Set.new(%w[srcdoc sandbox http-equiv]).freeze
	REF_ATTRIBUTES = Set.new(%w[href src action formaction lowsrc dynsrc background ping]).freeze

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
				v.gsub('"', "&quot;")
			when Symbol
				v.name.tr("_", "-").gsub('"', "&quot;")
			when Integer, Float
				v.to_s
			when Date
				v.iso8601
			when Time
				v.respond_to?(:iso8601) ? v.iso8601 : v.strftime("%Y-%m-%dT%H:%M:%S%:z")
			when Hash
				case k
				when :style
					generate_styles(v).gsub('"', "&quot;")
				else
					generate_nested_attributes(v, "#{name}-", buffer)
				end
			when Array
				case k
				when :style
					generate_styles(v).gsub('"', "&quot;")
				else
					generate_nested_tokens(v)
				end
			when Set
				case k
				when :style
					generate_styles(v).gsub('"', "&quot;")
				else
					generate_nested_tokens(v.to_a)
				end
			when Phlex::SGML::SafeObject
				v.to_s.gsub('"', "&quot;")
			else
				raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
			end

			lower_name = name.downcase

			unless Phlex::SGML::SafeObject === v
				normalized_name = lower_name.delete("^a-z-")

				if value != true && REF_ATTRIBUTES.include?(normalized_name)
					case value
					when String
						if value.downcase.delete("^a-z:").start_with?("javascript:")
							# We just ignore these because they were likely not specified by the developer.
							next
						end
					else
						raise Phlex::ArgumentError.new("Invalid attribute value for #{k}: #{v.inspect}.")
					end
				end

				if normalized_name.bytesize > 2 && normalized_name.start_with?("on") && !normalized_name.include?("-")
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end

				if UNSAFE_ATTRIBUTES.include?(normalized_name)
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end
			end

			if name.match?(/[<>&"']/)
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

				if name.match?(/[<>&"']/)
					raise Phlex::ArgumentError.new("Unsafe attribute name detected: #{k}.")
				end
			end

			case v
			when true
				buffer << " " << base_name << name
			when String
				buffer << " " << base_name << name << '="' << v.gsub('"', "&quot;") << '"'
			when Symbol
				buffer << " " << base_name << name << '="' << v.name.tr("_", "-").gsub('"', "&quot;") << '"'
			when Integer, Float
				buffer << " " << base_name << name << '="' << v.to_s << '"'
			when Hash
				generate_nested_attributes(v, "#{base_name}#{name}-", buffer)
			when Array
				buffer << " " << base_name << name << '="' << generate_nested_tokens(v) << '"'
			when Set
				buffer << " " << base_name << name << '="' << generate_nested_tokens(v.to_a) << '"'
			when Phlex::SGML::SafeObject
				buffer << " " << base_name << name << '="' << v.to_s.gsub('"', "&quot;") << '"'
			else
				raise Phlex::ArgumentError.new("Invalid attribute value #{v.inspect}.")
			end

			if root_key
				base_name = original_base_name
			end

			buffer
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
				if i > 0
					buffer << sep << token
				else
					buffer << token
				end
			when Symbol
				if i > 0
					buffer << sep << token.name.tr("_", "-")
				else
					buffer << token.name.tr("_", "-")
				end
			when Integer, Float, Phlex::SGML::SafeObject
				if i > 0
					buffer << sep << token.to_s
				else
					buffer << token.to_s
				end
			when Array
				if token.length > 0
					if i > 0
						buffer << sep << generate_nested_tokens(token, sep, gsub_from, gsub_to)
					else
						buffer << generate_nested_tokens(token, sep, gsub_from, gsub_to)
					end
				end
			when nil
				# Do nothing
			else
				raise Phlex::ArgumentError.new("Invalid token type: #{token.class}.")
			end

			i += 1
		end

		buffer.gsub('"', "&quot;")
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
