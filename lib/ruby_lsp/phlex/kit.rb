# frozen_string_literal: true

module RubyLsp
	module Phlex
		# Kit calls like `Card(title: "Hi")` are methods defined in a string eval
		# when the component's constant is added, so the indexer can't see them.
		module KitCall
			include Requests::Support::Common

			def initialize(response_builder, index, node_context, dispatcher)
				@response_builder = response_builder
				@index = index
				@node_context = node_context

				dispatcher.register(self, :on_call_node_enter)
			end

			private def component_entries(node)
				name = node.name.name

				return unless /\A[A-Z]/ === name

				case node.receiver
				in nil
					ancestors.lazy.filter_map { |ancestor| component(@index.resolve("#{ancestor}::#{name}", [])) }.first ||
						component(@index.resolve(name, @node_context.nesting))
				in Prism::ConstantReadNode | Prism::ConstantPathNode => receiver
					component(@index.resolve("#{receiver.slice}::#{name}", @node_context.nesting))
				else
					nil
				end
			end

			private def ancestors(name = @node_context.fully_qualified_name)
				@index.linearized_ancestors_of(name)
			rescue RubyIndexer::Index::NonExistingNamespaceError
				[]
			end

			# Kits only define methods for Phlex::SGML subclasses.
			private def component(entries)
				entries if entries&.any? { |entry| RubyIndexer::Entry::Class === entry && ancestors(entry.name).include?("Phlex::SGML") }
			end
		end

		class KitDefinition
			include KitCall

			def on_call_node_enter(node)
				component_entries(node)&.each do |entry|
					@response_builder << Interface::LocationLink.new(
						target_uri: entry.uri.to_s,
						target_range: range_from_location(entry.location),
						target_selection_range: range_from_location(entry.name_location),
					)
				end
			end
		end

		class KitHover
			include KitCall

			def on_call_node_enter(node)
				entries = component_entries(node)

				return unless entries

				name = entries.first.name
				signature = @index.resolve_method("initialize", name)&.first&.signatures&.first&.format

				categorized_markdown_from_index_entries("#{name}(#{signature})", entries).each do |category, content|
					@response_builder.push(content, category:)
				end
			end
		end
	end
end
