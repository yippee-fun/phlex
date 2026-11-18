# frozen_string_literal: true

class Phlex::HTML < Phlex::SGML
	extend Phlex::SGML::Elements
	include VoidElements, StandardElements

	# Output an HTML doctype.
	def doctype
		state = @_state
		return unless state.should_render?

		state.buffer << "<!doctype html>"
		nil
	end

	# Outputs an `<svg>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/SVG/Element/svg)
	# [Spec](https://html.spec.whatwg.org/#the-svg-element)
	def svg(*, **, &)
		if block_given?
			super { render Phlex::SVG.new(&) }
		else
			super
		end
	end

	# Override to provide a filename for the HTML file
	def filename
		nil
	end

	# Returns the string "text/html"
	def content_type
		"text/html"
	end

	# Output an HTML tag dynamically, e.g:
	#
	# ```ruby
	# @tag_name = :h1
	# tag(@tag_name, class: "title")
	# ```
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
		elsif (tag = VoidElements.__registered_elements__[name])
			void = true
		elsif (registrar = __element_registrar__(name))
			tag = registrar.__registered_elements__[name]
			void = registrar.__registered_void_elements__.key?(name)
		elsif (tag = name.name.tr("_", "-")).include?("-") && tag.match?(/\A[a-z][a-z0-9-]*\z/)
			void = false
		else
			raise Phlex::ArgumentError.new("Invalid HTML tag: #{name}")
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

					buffer << ::Phlex::ATTRIBUTE_CACHE.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
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
						buffer << Phlex::ATTRIBUTE_CACHE.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << ">"
					end

					begin
						if :svg == name
							render Phlex::SVG.new(&)
						else
							__yield_content__(&)
						end
					ensure
						buffer << "</#{tag}>"
					end
				else # without content
					buffer << "<#{tag}"
					begin
						buffer << ::Phlex::ATTRIBUTE_CACHE.fetch(attributes) { Phlex::SGML::Attributes.generate_attributes(attributes) }
					ensure
						buffer << "></#{tag}>"
					end
				end
			else # without attributes
				if block_given # with content block
					buffer << ("<#{tag}>")
					begin
						if :svg == name
							render Phlex::SVG.new(&)
						else
							__yield_content__(&)
						end
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
