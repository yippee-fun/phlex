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

			class Secret < Phlex::HTML
				def view_template = plain("secret")
			end

			private_constant :Secret

			class Swappable < Phlex::HTML
				def initialize(*) = nil
				def view_template = plain("swappable 1")
			end

			module Nested
				class Badge < Phlex::HTML
					def initialize(label) = @label = label
					def view_template = span { @label }
				end
			end
		end

		class Replacement < Phlex::HTML
			def initialize(*) = nil
			def view_template = plain("swappable 2")
		end

		ORIGINAL = Components::Swappable

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
				@log = []
			end

			# Replaces the component, as a reloader might, while the arguments are evaluated.
			private def swap(to = Replacement)
				Components.__send__(:remove_const, :Swappable)
				Components.const_set(:Swappable, to)
				nil
			end

			private def title_for(name)
				@log << name
				name.to_s
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
				Card("Symbol", &:footer_text)
				Secret()
				begin
					Swappable(swap)
				ensure
					swap(ORIGINAL)
				end
				Card(title_for(:a), tone: title_for(:b)) { plain @log.join(",") }
				Failing() if @raising
			rescue ArgumentError => error
				plain "rescued #{error.message}"
			end
		end

		module Overriding
			extend Phlex::Kit

			class Card < Phlex::HTML
				def view_template = plain("overriding card")
			end

			def self.const_get(name, ...) = (name == :Card) ? Replacement : super
		end

		class OverridingConstGet < Phlex::HTML
			include Overriding

			def view_template
				Card()
				plain "!"
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
