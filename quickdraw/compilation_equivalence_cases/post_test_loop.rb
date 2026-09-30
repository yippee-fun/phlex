# frozen_string_literal: true

module EquivalenceCases
	module PostTestLoop
		class PostTestLoop < Phlex::HTML
			def view_template
				begin
					div { "once" }
				end while false # rubocop:disable Lint/Loop

				i = 0
				begin
					span { i.to_s }
					i += 1
				end until i > 1 # rubocop:disable Lint/Loop
			end
		end
	end
end
