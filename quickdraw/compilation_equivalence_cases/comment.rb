# frozen_string_literal: true

class Comment < Phlex::HTML
	def view_template
		comment { "hello world" }
		comment { "Begin rendering #{self.class.name}" }
	end
end
