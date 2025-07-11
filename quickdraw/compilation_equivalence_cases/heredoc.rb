class Heredoc < Phlex::HTML
	def view_template
		lines = 3
	  photo_effect = <<~JS
	    let dt = new DataTransfer()
	    for (let photo of photos) {
	      dt.items.add(photo)
	    }
	    $el.files = dt.files
	  JS
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
