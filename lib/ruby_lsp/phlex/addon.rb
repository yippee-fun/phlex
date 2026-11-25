# frozen_string_literal: true

require "ruby_lsp/addon"
require_relative "kit"

module RubyLsp
	module Phlex
		class Addon < ::RubyLsp::Addon
			def activate(global_state, message_queue)
				@global_state = global_state
			end

			def deactivate
			end

			def name
				"Phlex"
			end

			def version
				"0.1.0"
			end

			# Kit calls need RubyIndexer, which ruby-lsp 0.27 replaced with Rubydex.
			def create_definition_listener(response_builder, uri, node_context, dispatcher)
				return unless defined?(::RubyIndexer::Index)

				KitDefinition.new(response_builder, @global_state.index, node_context, dispatcher)
			end

			def create_hover_listener(response_builder, node_context, dispatcher)
				return unless defined?(::RubyIndexer::Index)

				KitHover.new(response_builder, @global_state.index, node_context, dispatcher)
			end
		end

		# ruby-lsp 0.27 replaced RubyIndexer with Rubydex, which has no Enhancement API.
		if defined?(::RubyIndexer::Enhancement)
			class IndexingEnhancement < RubyIndexer::Enhancement
				def on_call_node_enter(node)
					owner = @listener.current_owner

					return unless owner
					return unless :register_element == node.name

					case node.arguments&.arguments
					in [Prism::SymbolNode[unescaped: String => method_name], *rest]
						tag_name = case rest
							in [Prism::KeywordHashNode[elements: [*, Prism::AssocNode[key: Prism::SymbolNode[unescaped: "tag"], value: Prism::StringNode | Prism::SymbolNode => tag], *]]]
								tag.unescaped
							else
								method_name.tr("_", "-")
						end

						@listener.add_method(method_name, node.location, [
							RubyIndexer::Entry::Signature.new([
								RubyIndexer::Entry::KeywordRestParameter.new(name: :attributes),
								RubyIndexer::Entry::BlockParameter.new(name: :content),
							]),
						], visibility: :public, comments: "Outputs a `<#{tag_name}>` tag.")
					else
						# no-op
					end
				end
			end
		end
	end
end
