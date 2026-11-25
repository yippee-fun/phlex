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

	# Normalizers rewrite the attributes in place, so elements that have one keep
	# a keyword splat, which is always a fresh Hash.
	def self.attributes_parameter(method_name)
		ATTRIBUTE_NORMALIZERS.key?(method_name) ? "**attributes" : "attributes = nil"
	end

	# Every name registered by any class or module, so `tag` only searches a
	# component's ancestors for a name something has registered. Replaced rather
	# than mutated, so it stays shareable between Ractors.
	@registered_names = {}.freeze
	@registered_names_mutex = Mutex.new

	def self.registered_name?(name)
		@registered_names.key?(name)
	end

	def self.record_registered_name(name)
		return if @registered_names.key?(name)

		@registered_names_mutex.synchronize do
			names = @registered_names.merge(name => true)
			@registered_names = defined?(::Ractor) ? ::Ractor.make_shareable(names) : names.freeze
		end
	end

	def self.normalizer_call(method_name)
		if (normalizer = ATTRIBUTE_NORMALIZERS[method_name])
			"Phlex::SGML::Elements.#{normalizer}(attributes)"
		end
	end

	Registry = Data.define(:elements, :void_elements)
	EMPTY_REGISTRY = Registry.new(elements: {}.freeze, void_elements: {}.freeze)
	REGISTRATION_MUTEX = Mutex.new

	# Frozen and replaced whole on each registration, so any Ractor can read it
	# and an element's tag is never seen without its void status.
	def __element_registry__
		@__element_registry__ || EMPTY_REGISTRY
	end

	def __registered_elements__
		(@__element_registry__ || EMPTY_REGISTRY).elements
	end

	def __registered_void_elements__
		(@__element_registry__ || EMPTY_REGISTRY).void_elements
	end

	def __element_registered__?(name)
		__registered_elements__.key?(name)
	end

	def register_element(method_name, tag: method_name.name.tr("_", "-"))
		tag = String.new(tag.to_s).freeze

		# Registered before the method is defined, so recompiling what inlined it reads the new tag.
		REGISTRATION_MUTEX.synchronize do
			registry = __element_registry__

			@__element_registry__ = Registry.new(
				elements: registry.elements.merge(method_name => tag).freeze,
				void_elements: registry.void_elements.except(method_name).freeze,
			)
		end

		Phlex::SGML::Elements.record_registered_name(method_name)

		# Aliasing the method to itself suppresses Ruby's method redefinition warning.
		alias_method(method_name, method_name) if method_defined?(method_name)

		class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
			# frozen_string_literal: true

			def #{method_name}(#{Phlex::SGML::Elements.attributes_parameter(method_name)})
				state = @_state
				buffer = state.buffer
				block_given = block_given?

				unless state.should_render?
					yield(self) if block_given
					return nil
				end

				unless Hash === attributes || attributes.nil?
					raise ::Phlex::ArgumentError.new("Expected attributes to be keyword arguments or a Hash.")
				end

				if attributes && attributes.length > 0 # with attributes
					if block_given # with content block
						buffer << "<#{tag}"
						begin
							#{Phlex::SGML::Elements.normalizer_call(method_name)}
							state.attribute_cache.append(buffer, attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
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
							state.attribute_cache.append(buffer, attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
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

		method_name
	end

	def __register_void_element__(method_name, tag: method_name.name.tr("_", "-"))
		tag = String.new(tag.to_s).freeze

		REGISTRATION_MUTEX.synchronize do
			registry = __element_registry__

			@__element_registry__ = Registry.new(
				elements: registry.elements.merge(method_name => tag).freeze,
				void_elements: registry.void_elements.merge(method_name => tag).freeze,
			)
		end

		Phlex::SGML::Elements.record_registered_name(method_name)

		# Aliasing the method to itself suppresses Ruby's method redefinition warning.
		alias_method(method_name, method_name) if method_defined?(method_name)

		class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
			# frozen_string_literal: true

			def #{method_name}(#{Phlex::SGML::Elements.attributes_parameter(method_name)})
				state = @_state

				return unless state.should_render?

				buffer = state.buffer

				unless Hash === attributes || attributes.nil?
					raise ::Phlex::ArgumentError.new("Expected attributes to be keyword arguments or a Hash.")
				end

				if attributes && attributes.length > 0 # with attributes
					buffer << "<#{tag}"
					begin
						#{Phlex::SGML::Elements.normalizer_call(method_name)}
						state.attribute_cache.append(buffer, attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << ">"
					end
				else # without attributes
					buffer << "<#{tag}>"
				end

				nil
			end
		RUBY

		method_name
	end
end
