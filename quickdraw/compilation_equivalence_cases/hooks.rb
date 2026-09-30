# frozen_string_literal: true

module EquivalenceCases
	module Hooks
		class NoRender < Phlex::HTML
			def view_template
				div { "never" }
			end

			private def render? = false
		end

		class Hooks < Phlex::HTML
			def view_template
				div { "main" }
			end

			private def before_template
				div { "before" }
				super
			end

			private def after_template
				div { "after" }
				super
			end

			private def around_template
				div(class: "around") { super }
			end
		end
	end
end
