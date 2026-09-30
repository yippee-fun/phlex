# frozen_string_literal: true

module EquivalenceCases
	module HelperMethods
		class HelperMethods < Phlex::HTML
			def view_template
				header
				body_part("x")
				private_part
			end

			def header
				h1 { "Header" }
			end

			def body_part(txt)
				p { txt }
			end

			private def private_part
				footer { "priv" }
			end
		end
	end
end
