# frozen_string_literal: true

class EmojiTest < Quickdraw::Test
	class Example < 💪::HTML
		def view_template
			h1 { "💪" }
		end
	end

	test "💪" do
		assert_equal Example.new.call, %(<h1>💪</h1>)
	end
end
