# frozen_string_literal: true

require "ruby_lsp/internal"
require "ruby_lsp/phlex/addon"

class RubyLspIndexingTest < Quickdraw::Test
	test "indexes a registered element with its default tag" do
		entry = index_and_resolve(<<~RUBY, "trix_editor", "Component")
			class Component < Phlex::HTML
				register_element :trix_editor
			end
		RUBY

		assert_equal entry.comments, "Outputs a `<trix-editor>` tag."
	end

	test "indexes a registered element with a custom tag" do
		entry = index_and_resolve(<<~RUBY, "foo", "Component")
			class Component < Phlex::HTML
				register_element :foo, tag: "x-foo"
			end
		RUBY

		assert_equal entry.comments, "Outputs a `<x-foo>` tag."
	end

	test "ignores register_element outside a class" do
		index = RubyIndexer::Index.new
		index.index_single(URI::Generic.from_path(path: "/fake.rb"), "register_element :foo")

		assert_equal index["foo"], nil
	end

	private def index_and_resolve(source, method_name, owner)
		index = RubyIndexer::Index.new
		index.index_single(URI::Generic.from_path(path: "/fake.rb"), source)
		index.resolve_method(method_name, owner).first
	end
end
