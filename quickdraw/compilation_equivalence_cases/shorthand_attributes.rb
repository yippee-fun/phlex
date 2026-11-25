# frozen_string_literal: true

module EquivalenceCases
	module ShorthandAttributes
		class LocalShorthand < Phlex::HTML
			def view_template
				title = "Tip"
				a(href: "/x", title:) { "link" }
			end
		end

		class MethodShorthand < Phlex::HTML
			def view_template
				a(href: "/x", title:) { "link" }
				p { @calls.to_s }
			end

			private def title
				@calls = (@calls || 0) + 1
				"Tip"
			end
		end

		class SeveralShorthands < Phlex::HTML
			def view_template
				id = "main"
				div(id:, title:, data: { count: }) { "content" }
			end

			private def title = "Tip"
			private def count = 3
		end

		class SoleShorthand < Phlex::HTML
			def view_template
				title = "Tip"
				span(title:)
			end
		end

		class KeywordShorthand < Phlex::HTML
			def view_template
				card
				card(class: "wide")
				div(if:) { "method" }
			end

			private def card(class: "card") = div(class:) { "local" }
			private def if = "shown"
		end
	end
end
