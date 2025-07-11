# frozen_string_literal: true

class CaptureWithBlock < Phlex::HTML
	def view_template
		before_template do
			div { "content" }
		end
		
		div { @section_content }
	end

	def before_template(&)
		# This will execute the block early, like deferred render,
		@section_content = capture(&)
	end
end