class Heredoc < Phlex::HTML
	def view_template
		unknown {
			p(<<~FIRST, <<~SECOND).gsub() { <<~THIRD }
			  This is a heredoc.
				It has multiple lines of text.
				And it's all going in this <p> tag.
			FIRST
			  This is another thing
			SECOND
				Yet another string
			THIRD
		}
	end

	def unknown
		yield
	end
end
