# frozen_string_literal: true

class Phlex::SVG < Phlex::SGML
	include StandardElements

	# Returns the string "image/svg+xml"
	def content_type
		"image/svg+xml"
	end

	# Override to provide a filename for the SVG file
	def filename
		nil
	end

	def cdata(content = nil, &block)
		state = @_state
		return unless state.should_render?

		if !block && String === content
			state.buffer << "<![CDATA[" << content.gsub("]]>", "]]]]><![CDATA[>") << "]]>"
		elsif block && nil == content
			state.buffer << "<![CDATA[" << capture(&block).gsub("]]>", "]]]]><![CDATA[>") << "]]>"
		else

			raise Phlex::ArgumentError.new("Expected a String or block.")
		end

		nil
	end

	def tag(name, **attributes, &)
		state = @_state
		block_given = block_given?
		buffer = state.buffer

		unless state.should_render?
			yield(self) if block_given
			return nil
		end

		unless Symbol === name
			raise Phlex::ArgumentError.new("Expected the tag name to be a Symbol.")
		end

		if (tag = StandardElements.__registered_elements__[name])
			void = false
		elsif (registrar = __element_registrar__(name))
			registry = registrar.__element_registry__
			tag = registry.elements[name]
			void = registry.void_elements.key?(name)
		elsif (tag = name.name.tr("_", "-")).include?("-") && tag.match?(/\A[a-z][a-z0-9-]*\z/)
			void = false
		else
			raise Phlex::ArgumentError.new("Invalid SVG tag: #{name}")
		end

		if void
			if block_given
				raise Phlex::ArgumentError.new("Void elements cannot have content blocks.")
			end

			if attributes.length > 0 # with attributes
				buffer << "<#{tag}"
				begin
					if (normalizer = Phlex::SGML::Elements::ATTRIBUTE_NORMALIZERS[name])
						Phlex::SGML::Elements.public_send(normalizer, attributes)
					end

					buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
				ensure
					buffer << ">"
				end
			else # without attributes
				buffer << "<#{tag}>"
			end

			nil
		else
			if attributes.length > 0 # with attributes
				if block_given # with content block
					buffer << "<#{tag}"
					begin
						buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << ">"
					end

					begin
						__yield_content__(&)
					ensure
						buffer << "</#{tag}>"
					end
				else # without content
					buffer << "<#{tag}"
					begin
						buffer << state.attribute_cache.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << "></#{tag}>"
					end
				end
			else # without attributes
				if block_given # with content block
					buffer << ("<#{tag}>")
					begin
						__yield_content__(&)
					ensure
						buffer << "</#{tag}>"
					end
				else # without content
					buffer << "<#{tag}></#{tag}>"
				end
			end

			flush if "head" == tag

			nil
		end
	end
end
