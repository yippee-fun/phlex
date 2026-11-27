# frozen_string_literal: true

class WithContentTest < Quickdraw::Test
	class Card < Phlex::HTML
		def initialize(title = nil)
			@title = title
		end

		def view_template(&)
			article do
				h1 { @title } if @title
				yield(self) if block_given?
			end
		end
	end

	class Page < Phlex::HTML
		def initialize(card)
			@card = card
		end

		def view_template
			main { render @card }
		end
	end

	test "with_content returns the component" do
		card = Card.new
		assert card.with_content { "Hi" }.equal?(card)
	end

	test "with_content renders the stored block later" do
		card = Card.new("Title").with_content { "Hi" }
		assert_equal Page.call(card), %(<main><article><h1>Title</h1>Hi</article></main>)
	end

	test "with_content blocks receive what view_template yields" do
		card = Card.new.with_content { |c| c.strong { "Hi" } }
		assert_equal card.call, %(<article><strong>Hi</strong></article>)
	end

	test "a block passed to render takes precedence" do
		page = Class.new(Phlex::HTML) do
			define_method(:view_template) do
				render(Card.new.with_content { "stored" }) { "given" }
			end
		end

		assert_equal page.call, %(<article>given</article>)
	end

	test "the class method passes its arguments to new" do
		card = Card.with_content("Title") { "Hi" }
		assert Card === card
		assert_equal Page.call(card), %(<main><article><h1>Title</h1>Hi</article></main>)
	end

	test "with_content requires a block" do
		assert_equal assert_raises(Phlex::ArgumentError) { Card.new.with_content }.message, "with_content requires a block."
		assert_equal assert_raises(Phlex::ArgumentError) { Card.with_content }.message, "with_content requires a block."
	end

	test "new does not capture a block" do
		assert_equal Card.new { "ignored" }.call, %(<article></article>)
	end

	test "the class method passes keyword arguments to new" do
		component = Class.new(Phlex::HTML) do
			def initialize(title:) = @title = title

			def view_template(&) = h1(title: @title, &)
		end

		assert_equal component.with_content(title: "a") { "b" }.call, %(<h1 title="a">b</h1>)
	end
end
