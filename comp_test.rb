# frozen_string_literal: true

require "phlex"

class FlexHTML < Phlex::HTML
	def view_template
		__buffer__ = @_state.buffer; __buffer__ << "<h1></h1><h1>"
		__yield_content__ { "Hello" }; __buffer__ << "</h1><div" \
		<< __attributes__(class: "foo"); __buffer__ << "></div><div" \
		<< __attributes__(class: "foo"); __buffer__ << ">"; __yield_content__ { "World" }; __buffer__ << "</div>"
	end
end

puts FlexHTML.new.call
