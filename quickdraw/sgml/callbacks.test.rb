# frozen_string_literal: true

class CallbacksTest < Quickdraw::Test
	class Example < Phlex::HTML
		def before_template
			i { "1" }
		end

		def around_template
			i { "2" }

			super do
				i { "3" }
				yield
				i { "5" }
			end

			i { "6" }
		end

		def after_template
			i { "7" }
		end

		def view_template
			i { "4" }
		end
	end

	test "callbacks are called in the correct order" do
		assert_equal Example.call, "<i>1</i><i>2</i><i>3</i><i>4</i><i>5</i><i>6</i><i>7</i>"
	end
end
