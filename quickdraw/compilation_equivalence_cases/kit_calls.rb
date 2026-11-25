# frozen_string_literal: true

module EquivalenceCases
	module KitCalls
		module Components
			extend Phlex::Kit

			class Card < Phlex::HTML
				def initialize(title = "untitled", tone: nil, **attributes)
					@title = title
					@tone = tone
					@attributes = attributes
				end

				def view_template(&)
					article(class: @tone, **@attributes) do
						h2 { @title }
						yield(self) if block_given?
					end
				end

				def footer_text = "footer"
			end

			class Failing < Phlex::HTML
				def view_template
					raise ArgumentError, "failing"
				end
			end

			module Nested
				class Badge < Phlex::HTML
					def initialize(label) = @label = label
					def view_template = span { @label }
				end
			end
		end

		class KitCalls < Phlex::HTML
			include Components
			include Components::Nested

			def self.equivalence_scenarios
				{
					"fragment" => -> (klass) { klass.new.call(fragments: [:f]) },
					"raising" => -> (klass) { klass.new(raising: true).call },
				}
			end

			def initialize(raising: false)
				@raising = raising
			end

			def view_template(&block)
				Card("One", tone: :warm) { p { "body" } }
				Card({ title: "positional hash" })
				Card(id: "card") { |card| plain card.footer_text }
				Card(*["splat"], **{ tone: :cool })
				Badge("nested")
				fragment(:f) { Card("Fragment") }
				[1, 2].each { |i| Badge(i) }
				value = Card("Break") { break :broken }
				plain value.inspect
				Card("Forwarded", &block)
				Card("Lambda", &-> (_card) { plain "from lambda" })
				Failing() if @raising
			rescue ArgumentError => error
				plain "rescued #{error.message}"
			end
		end

		class OverridesKitMethod < Phlex::HTML
			include Components

			def view_template
				Card("ignored")
			end

			def Card(title) = plain("own #{title}")
		end
	end
end
