# frozen_string_literal: true

class ExampleComponent < Phlex::HTML
	def view_template(&)
		div(&)
	end
end

class StandardElementExample < Phlex::HTML
	def initialize(execution_checker = -> {})
		@execution_checker = execution_checker
	end

	def view_template
		doctype
		div {
			comment { h1(id: "target") }
			h1 { "Before" }
			img(src: "before.jpg")
			render ExampleComponent.new { "Should not render" }
			whitespace
			comment { "This is a comment" }
			fragment("target") do
				h1(id: "target") {
					plain "Hello"
					strong { "World" }
					img(src: "image.jpg")
				}
			end
			@execution_checker.call
			strong { "Here" }
			fragment("image") do
				img(id: "image", src: "after.jpg")
			end
			h1(id: "target") { "After" }
		}
	end
end
