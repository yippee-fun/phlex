# frozen_string_literal: true

require "ruby_lsp/internal"

# These features use RubyIndexer, which ruby-lsp 0.27 replaced with Rubydex.
return unless defined?(RubyIndexer::Index)
require "ruby_lsp/test_helper"

class RubyLspKitTest < Quickdraw::Test
	include RubyLsp::TestHelper

	SOURCE = <<~RUBY
		module Components
			extend Phlex::Kit
		end

		# A card.
		class Components::Card < Phlex::HTML
			def initialize(title:, size: :md) = nil
		end

		class Page < Phlex::HTML
			include Components

			def view_template
				Card(title: "Hi")
				Components::Card(title: "Hi")
				Missing(title: "Hi")
				Array(1)
			end
		end

		module Components
			class Grid < Phlex::HTML
				def view_template
					Card(title: "Hi")
				end
			end
		end
	RUBY

	test "goes to the component from a kit call on an included kit" do
		assert_equal definition_lines(13, 3), [5]
	end

	test "goes to the component from a kit call with a constant receiver" do
		assert_equal definition_lines(14, 15), [5]
	end

	test "goes to the component from a kit call within the kit's namespace" do
		assert_equal definition_lines(23, 5), [5]
	end

	test "ignores capitalised calls that aren't components" do
		assert_equal definition_lines(15, 3), []
		assert_equal definition_lines(16, 3), []
	end

	test "prefers the included kit's component over a lexical constant" do
		source = <<~RUBY
			module Components
				extend Phlex::Kit
			end

			class Components::Card < Phlex::HTML
			end

			class Card < Phlex::HTML
			end

			class Page < Phlex::HTML
				include Components

				def view_template
					Card()
				end
			end
		RUBY

		assert_equal definition_lines(14, 3, source), [4]
	end

	test "shows the component and its initializer on hover" do
		hover = request("textDocument/hover", 13, 3)

		assert hover.contents.value.include?("Components::Card")
		assert hover.contents.value.include?("A card.")
		assert hover.contents.value.include?("(title:, size: <default>)")
	end

	private def definition_lines(line, character, source = SOURCE)
		Array(request("textDocument/definition", line, character, source)).map { |link| link.target_range.start.line }
	end

	private def request(method, line, character, source = SOURCE)
		with_server(source) do |server, uri|
			server.global_state.index.index_single(URI::Generic.from_path(path: "/phlex/html.rb"), "module Phlex; class SGML; end; class HTML < SGML; end; end")
			server.global_state.index.index_single(URI::Generic.from_path(path: "/core/array.rb"), "class Array; end")
			server.process_message(id: 1, method:, params: { textDocument: { uri: }, position: { line:, character: } })
			pop_result(server).response
		end
	end
end
