# frozen_string_literal: true

# `data` is a URL on `object`, unless it's a Hash of `data-*` attributes.
class DataReferences < Phlex::HTML
	def initialize
		@url = "javascript:alert(1)"
		@data = { controller: "x" }
	end

	def view_template
		object(data: "javascript:alert(1)")
		object(data: "/files/report.pdf")
		object(data: @url)
		object(data: @data)
		div(data: { controller: "x" })
	end
end
