# frozen_string_literal: true

module EquivalenceCases
	module HeadFlush
		class HeadFlush < Phlex::HTML
			def view_template
				doctype
				html do
					head do
						title { "T" }
						meta(charset: "utf-8")
					end
					flush
					body { div { "b" } }
				end
			end
		end
	end
end
