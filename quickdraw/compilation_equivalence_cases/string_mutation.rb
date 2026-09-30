# rubocop:disable Style/FrozenStringLiteralComment
module EquivalenceCases
	module StringMutation
		class StringMutation < Phlex::HTML
			def view_template
				text = "a"
				text << "b"
				div { text }
			end
		end
	end
end
# rubocop:enable Style/FrozenStringLiteralComment
