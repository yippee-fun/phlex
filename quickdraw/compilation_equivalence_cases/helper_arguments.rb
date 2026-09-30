# frozen_string_literal: true

module EquivalenceCases
	module HelperArguments
		class WhitespaceArguments < Phlex::HTML
			def view_template
				div { "x" }
				whitespace(1)
			end
		end

		class CommentArguments < Phlex::HTML
			def view_template
				div { "x" }
				comment(1) { "c" }
			end
		end

		class DoctypeArguments < Phlex::HTML
			def view_template
				div { "x" }
				doctype(1)
			end
		end
	end
end
