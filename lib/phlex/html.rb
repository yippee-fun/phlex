# frozen_string_literal: true

class Phlex::HTML < Phlex::SGML
	# Elements `tag` won't render, since its name may come from a user.
	UNSAFE_TAGS = Set.new(%w[script style base]).freeze

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

		# The name passed to `tag` may come from a user, so it can't render an
		# element whose content or attributes run as code or change where code loads from.
		if (unsafe_tag = StandardElements.__registered_elements__[name] || VoidElements.__registered_elements__[name]) && UNSAFE_TAGS.include?(unsafe_tag)
			raise Phlex::ArgumentError.new("`tag` can't render <#{unsafe_tag}>. Call `#{unsafe_tag}` directly instead.")
		end

		if (tag = StandardElements.__registered_elements__[name]) || ((tag = name.name.tr("_", "-")).include?("-") && tag.match?(/\A[a-z0-9-]+\z/))
			if attributes.length > 0 # with attributes
				if block_given # with content block
					buffer << "<#{tag}"
					begin
						buffer << (Phlex::ATTRIBUTE_CACHE[attributes] ||= Phlex::SGML::Attributes.generate_attributes(attributes))
					ensure
						buffer << ">"
					end
					begin
						if tag == "svg"
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
						buffer << (::Phlex::ATTRIBUTE_CACHE[attributes] ||= Phlex::SGML::Attributes.generate_attributes(attributes))
					ensure
						buffer << "></#{tag}>"
					end
				end
			else # without attributes
				if block_given # with content block
					buffer << ("<#{tag}>")
					begin
						if tag == "svg"
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
		elsif (tag = VoidElements.__registered_elements__[name])
			if block_given
				raise Phlex::ArgumentError.new("Void elements cannot have content blocks.")
			end

			if attributes.length > 0 # with attributes
				buffer << "<#{tag}"
				begin
					buffer << (::Phlex::ATTRIBUTE_CACHE[attributes] ||= Phlex::SGML::Attributes.generate_attributes(attributes))
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
