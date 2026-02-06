# frozen_string_literal: true

class Phlex::SVG < Phlex::SGML
	autoload :StandardElements, "phlex/svg/standard_elements"

	include StandardElements

	# Returns the string "image/svg+xml"
	def content_type
		"image/svg+xml"
	end

	# Override to provide a filename for the SVG file
	def filename
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

		if (tag = StandardElements.__registered_elements__[name]) || ((tag = name.name.tr("_", "-")).include?("-") && tag.match?(/\A[a-z0-9-]+\z/))
			if attributes.length > 0 # with attributes
				if block_given # with content block
					buffer << "<#{tag}" << (Phlex::ATTRIBUTE_CACHE[attributes] ||= __attributes__(attributes)) << ">"
					__yield_content__(&)
					buffer << "</#{tag}>"
				else # without content
					buffer << "<#{tag}" << (::Phlex::ATTRIBUTE_CACHE[attributes] ||= __attributes__(attributes)) << "></#{tag}>"
				end
			else # without attributes
				if block_given # with content block
					buffer << ("<#{tag}>")
					__yield_content__(&)
					buffer << "</#{tag}>"
				else # without content
					buffer << "<#{tag}></#{tag}>"
				end
			end
		else
			raise Phlex::ArgumentError.new("Invalid SVG tag: #{name}")
		end
	end
end
