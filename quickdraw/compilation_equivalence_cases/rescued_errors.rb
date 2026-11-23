# frozen_string_literal: true

# An element whose attributes or content raise still closes its tags, so
# output after a rescued error isn't read as part of an unclosed tag.
class RescuedErrors < Phlex::HTML
	def initialize
		@bad = { _: "javascript:alert(1)" }
	end

	def view_template
		attempt { div(href: @bad) }
		attempt { div(href: @bad) { "content" } }
		attempt { img(src: @bad) }
		attempt { div(class: "a") { raise Phlex::ArgumentError } }
		attempt { span { raise Phlex::ArgumentError } }
		plain "after"
	end

	private def attempt
		yield
	rescue Phlex::ArgumentError
		nil
	end
end
