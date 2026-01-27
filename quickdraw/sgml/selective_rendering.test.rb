# frozen_string_literal: true

class SelectiveRenderingTest < Quickdraw::Test
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

	class VoidElementExample < Phlex::HTML
		def view_template
			doctype
			div {
				comment { h1(id: "target") }
				h1 { "Before" }
				img(src: "before.jpg")
				whitespace
				comment { "This is a comment" }
				h1 {
					plain "Hello"
					strong { "World" }
					fragment("target") do
						img(id: "target", src: "image.jpg")
					end
				}
				img(src: "after.jpg")
				h1(id: "target") { "After" }
			}
		end
	end

	class WithCaptureBlock < Phlex::HTML
		def view_template
			h1(id: "before") { "Before" }
			fragment("around") do
				div(id: "around") do
					capture do
						fragment("inside") do
							h1(id: "inside") { "Inside" }
						end
					end
				end
			end
			fragment("after") do
				h1(id: "after") { "After" }
			end
		end
	end

	test "renders the just the target fragment" do
		output = StandardElementExample.new.call(fragments: ["target"])
		assert_equal output, %(<h1 id="target">Hello<strong>World</strong><img src="image.jpg"></h1>)
	end

	test "works with void elements" do
		output = VoidElementExample.new.call(fragments: ["target"])
		assert_equal output, %(<img id="target" src="image.jpg">)
	end

	test "supports multiple fragments" do
		output = StandardElementExample.new.call(fragments: ["target", "image"])
		assert_equal output, %(<h1 id="target">Hello<strong>World</strong><img src="image.jpg"></h1><img id="image" src="after.jpg">)
	end

	test "halts early after all fragments are found" do
		called = false
		checker = -> { called = true }
		StandardElementExample.new(checker).call(fragments: ["target"])

		refute called
	end

	test "with a capture block doesn't render the capture block" do
		output = WithCaptureBlock.new.call(fragments: ["after"])
		assert_equal output, %(<h1 id="after">After</h1>)
	end

	test "with a capture block renders the capture block when selected" do
		output = WithCaptureBlock.new.call(fragments: ["around"])
		assert_equal output, %(<div id="around">&lt;h1 id=&quot;inside&quot;&gt;Inside&lt;/h1&gt;</div>)
	end

	test "with a capture block doesn't select from the capture block" do
		output = WithCaptureBlock.new.call(fragments: ["inside"])
		assert_equal output, ""
	end
end
