# frozen_string_literal: true

module Example
	extend Phlex::Kit

	class Page < Phlex::HTML
		def view_template
			div { "Hello" }
		end

		def foobar
		end
	end
end
