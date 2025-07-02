# frozen_string_literal: true

module Phlex::SGML::Elements
	COMMA_SEPARATED_TOKENS = {
		img: <<~RUBY,
			if Array === (srcset_attribute = attributes[:srcset])
				attributes[:srcset] = __nested_tokens__(srcset_attribute, ", ", ",", "%2C")
			end
		RUBY
		link: <<~RUBY,
			if Array === (media_attribute = attributes[:media])
				attributes[:media] = __nested_tokens__(media_attribute, ", ", ",", "%2C")
			end

			if Array === (sizes_attribute = attributes[:sizes])
				attributes[:sizes] = __nested_tokens__(sizes_attribute, ", ", ",", "%2C")
			end

			if Array === (imagesrcset_attribute = attributes[:imagesrcset])
				rel_attribute = attributes[:rel] || attributes["rel"]
				as_attribute = attributes[:as] || attributes["as"]

				if ("preload" == rel_attribute || :preload == rel_attribute) && ("image" == as_attribute || :image == as_attribute)
					attributes[:imagesrcset] = __nested_tokens__(imagesrcset_attribute, ", ", ",", "%2C")
				end
			end
		RUBY
		input: <<~RUBY,
			if Array === (accept_attribute = attributes[:accept])
				type_attribute = attributes[:type] || attributes["type"]

				if "file" == type_attribute || :file == type_attribute
					attributes[:accept] = __nested_tokens__(accept_attribute, ", ", ",", "%2C")
				end
			end
		RUBY
	}.freeze

	def __registered_elements__
		@__registered_elements__ ||= {}
	end

	def register_element(method_name, tag: method_name.name.tr("_", "-"))
		class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
			# frozen_string_literal: true

			def #{method_name}(**attributes)
				state = @_state
				buffer = state.buffer
				block_given = block_given?

				unless state.should_render?
					yield(self) if block_given
					return nil
				end

				if attributes.length > 0 # with attributes
					if block_given # with content block
						buffer << "<#{tag}"
						begin
							#{COMMA_SEPARATED_TOKENS[method_name]}
							buffer << (Phlex::ATTRIBUTE_CACHE[attributes] ||= __attributes__(attributes))
						ensure
							buffer << ">"
						end

						begin
							original_length = buffer.bytesize
							content = yield(self)
							if original_length == buffer.bytesize
								case content
								when ::Phlex::SGML::SafeObject
									buffer << content.to_s
								when String
									buffer << ::Phlex::Escape.html_escape(content)
								when Symbol
									buffer << ::Phlex::Escape.html_escape(content.name)
								when nil
									nil
								else
									if (formatted_object = format_object(content))
										buffer << ::Phlex::Escape.html_escape(formatted_object)
									end
								end
							end
						ensure
							buffer << "</#{tag}>"
						end
					else # without content
						buffer << "<#{tag}"
						begin
							#{COMMA_SEPARATED_TOKENS[method_name]}
							buffer << (::Phlex::ATTRIBUTE_CACHE[attributes] ||= __attributes__(attributes))
						ensure
							buffer << "></#{tag}>"
						end
					end
				else # without attributes
					if block_given # with content block
						buffer << "<#{tag}>"

						begin
							original_length = buffer.bytesize
							content = yield(self)
							if original_length == buffer.bytesize
								case content
								when ::Phlex::SGML::SafeObject
									buffer << content.to_s
								when String
									buffer << ::Phlex::Escape.html_escape(content)
								when Symbol
									buffer << ::Phlex::Escape.html_escape(content.name)
								when nil
									nil
								else
									if (formatted_object = format_object(content))
										buffer << ::Phlex::Escape.html_escape(formatted_object)
									end
								end
							end
						ensure
							buffer << "</#{tag}>"
						end
					else # without content
						buffer << "<#{tag}></#{tag}>"
					end
				end

				#{'flush' if tag == 'head'}

				nil
			end
		RUBY

		__registered_elements__[method_name] = tag

		method_name
	end

	def __register_void_element__(method_name, tag: method_name.name.tr("_", "-"))
		class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
			# frozen_string_literal: true

			def #{method_name}(**attributes)
				state = @_state

				return unless state.should_render?

				buffer = state.buffer

				if attributes.length > 0 # with attributes
					buffer << "<#{tag}"
					begin
						#{COMMA_SEPARATED_TOKENS[method_name]}
						buffer << (::Phlex::ATTRIBUTE_CACHE[attributes] ||= __attributes__(attributes))
					ensure
						buffer << ">"
					end
				else # without attributes
					buffer << "<#{tag}>"
				end

				nil
			end
		RUBY

		__registered_elements__[method_name] = tag

		method_name
	end
end
