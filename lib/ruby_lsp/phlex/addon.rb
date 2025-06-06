# frozen_string_literal: true

require "ruby_lsp/addon"

module RubyLsp
	module Phlex
		class Addon < ::RubyLsp::Addon
			def activate(global_state, message_queue)
			end

			def deactivate
			end

			def name
				"Phlex"
			end

			def version
				"0.1.0"
			end
		end

		class IndexingEnhancement < RubyIndexer::Enhancement
			def on_call_node_enter(node)
				name = node.name
				owner = @listener.current_owner
				location = node.location
				arguments = node.arguments&.arguments

				return unless owner
				return unless :register_element == name

				case arguments
				in [Prism::SymbolNode[unescaped: String => method_name], *]
					tag_name = method_name.tr("_", "-")
					arguments[1] in Prism::StringNode[unescaped: String => tag_name]

					@listener.add_method(method_name, location, [
						RubyIndexer::Entry::Signature.new([
							RubyIndexer::Entry::KeywordRestParameter.new(name: :attributes),
							RubyIndexer::Entry::BlockParameter.new(name: :content),
						]),
					], visibility: :public, comments: "Outputs a `<#{tag_name}>` tag.")
				end
			end
		end
	end
end
