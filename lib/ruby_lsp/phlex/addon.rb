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
				in [Prism::SymbolNode[unescaped: String => element_name], *]
					@listener.add_method(element_name, location, [
						RubyIndexer::Entry::Signature.new([
							RubyIndexer::Entry::KeywordRestParameter.new(name: :attributes),
							RubyIndexer::Entry::BlockParameter.new(name: :content),
						]),
					], visibility: :public)
				end
			end
		end
	end
end
