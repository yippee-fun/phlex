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

		if (tag = StandardElements.__registered_elements__[name] || __custom_element_name__(name))
			if block_given && tag == "svg"
				__standard_tag__(tag, attributes) { render Phlex::SVG.new(&) }
			else
				__standard_tag__(tag, attributes, &)
			end
		elsif (tag = VoidElements.__registered_elements__[name])
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
			raise Phlex::ArgumentError.new("Invalid HTML tag: #{name}")
		end
	end
end
