class Heredoc < Phlex::HTML
	def view_template
		lines = 3
		unknown {
			p { <<~FIRST }
        This is a heredoc.
        It has #{lines} lines of text.
        And it's all going in this <p> tag.
      FIRST
      plain(<<~TXT)
        This is some plain text.
      TXT
		}
	end

	def unknown
		yield
	end
end
