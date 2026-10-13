# frozen_string_literal: true

module Phlex::SGML::Elements
	# Elements whose attributes need rewriting before they're rendered.
	# Shared by the runtime element methods and the compiler.
	ATTRIBUTE_NORMALIZERS = {
		img: :normalize_img_attributes,
		link: :normalize_link_attributes,
		input: :normalize_input_attributes,
	}.freeze

	# The attributes each normalizer rewrites, so the compiler can serialise the
	# others on their own.
	NORMALIZED_ATTRIBUTES = {
		img: Set[:srcset],
		link: Set[:media, :sizes, :imagesrcset],
		input: Set[:accept],
	}.freeze

	def self.normalize_img_attributes(attributes)
		if Array === (srcset_attribute = attributes[:srcset])
			attributes[:srcset] = Phlex::SGML::Attributes.generate_nested_tokens(srcset_attribute, ", ", ",", "%2C")
		end

		attributes
	end

	def self.normalize_link_attributes(attributes)
		if Array === (media_attribute = attributes[:media])
			attributes[:media] = Phlex::SGML::Attributes.generate_nested_tokens(media_attribute, ", ", ",", "%2C")
		end

		if Array === (sizes_attribute = attributes[:sizes])
			attributes[:sizes] = Phlex::SGML::Attributes.generate_nested_tokens(sizes_attribute, ", ", ",", "%2C")
		end

		if Array === (imagesrcset_attribute = attributes[:imagesrcset])
			rel_attribute = attributes[:rel] || attributes["rel"]
			as_attribute = attributes[:as] || attributes["as"]

			if ("preload" == rel_attribute || :preload == rel_attribute) && ("image" == as_attribute || :image == as_attribute)
				attributes[:imagesrcset] = Phlex::SGML::Attributes.generate_nested_tokens(imagesrcset_attribute, ", ", ",", "%2C")
			end
		end

		attributes
	end

	def self.normalize_input_attributes(attributes)
		if Array === (accept_attribute = attributes[:accept])
			type_attribute = attributes[:type] || attributes["type"]

			if "file" == type_attribute || :file == type_attribute
				attributes[:accept] = Phlex::SGML::Attributes.generate_nested_tokens(accept_attribute, ", ", ",", "%2C")
			end
		end

		attributes
	end

	def self.normalizer_call(method_name)
		if (normalizer = ATTRIBUTE_NORMALIZERS[method_name])
			"Phlex::SGML::Elements.#{normalizer}(attributes)"
		end
	end

	def __registered_elements__
		@__registered_elements__ ||= {}
	end

	def __registered_void_elements__
		@__registered_void_elements__ ||= {}
	end

	# The built-in element modules call this once their bodies have registered
	# every element. It freezes both registries in place, without copying them,
	# so `tag` can read them from any Ractor. A later registration on a frozen
	# registry swaps in a frozen copy instead of mutating it.
	def __freeze_registries__
		__freeze_registry__(__registered_elements__)
		__freeze_registry__(__registered_void_elements__)
		nil
	end

	def register_element(method_name, tag: method_name.name.tr("_", "-"))
		# Aliasing the method to itself suppresses Ruby's method redefinition warning.
		alias_method(method_name, method_name) if method_defined?(method_name)

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
							#{Phlex::SGML::Elements.normalizer_call(method_name)}
							buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
						ensure
							buffer << ">"
						end

						begin
							original_length = state.output_bytesize
							content = yield(self)
							if original_length == state.output_bytesize
								case content
								when ::Phlex::SGML::SafeObject
									state.append(content.to_s)
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
							#{Phlex::SGML::Elements.normalizer_call(method_name)}
							buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
						ensure
							buffer << "></#{tag}>"
						end
					end
				else # without attributes
					if block_given # with content block
						buffer << "<#{tag}>"

						begin
							original_length = state.output_bytesize
							content = yield(self)
							if original_length == state.output_bytesize
								case content
								when ::Phlex::SGML::SafeObject
									state.append(content.to_s)
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

		__record_element__(method_name, tag, void: false)

		method_name
	end

	def __register_void_element__(method_name, tag: method_name.name.tr("_", "-"))
		# Aliasing the method to itself suppresses Ruby's method redefinition warning.
		alias_method(method_name, method_name) if method_defined?(method_name)

		class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
			# frozen_string_literal: true

			def #{method_name}(**attributes)
				state = @_state

				return unless state.should_render?

				buffer = state.buffer

				if attributes.length > 0 # with attributes
					buffer << "<#{tag}"
					begin
						#{Phlex::SGML::Elements.normalizer_call(method_name)}
						buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << ">"
					end
				else # without attributes
					buffer << "<#{tag}>"
				end

				nil
			end
		RUBY

		__record_element__(method_name, tag, void: true)

		method_name
	end

	private def __record_element__(method_name, tag, void:)
		elements = __registered_elements__
		void_elements = __registered_void_elements__

		if elements.frozen? || void_elements.frozen?
			tag = -tag.to_s
			@__registered_elements__ = __freeze_registry__(elements.merge(method_name => tag))
			@__registered_void_elements__ = __freeze_registry__(
				void ? void_elements.merge(method_name => tag) : void_elements.except(method_name)
			)
		else
			elements[method_name] = tag

			if void
				void_elements[method_name] = tag
			else
				void_elements.delete(method_name)
			end
		end
	end

	private def __freeze_registry__(registry)
		if defined?(::Ractor)
			::Ractor.make_shareable(registry)
		else
			registry.each_value(&:freeze).freeze
		end
	end
end
