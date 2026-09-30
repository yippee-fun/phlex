# frozen_string_literal: true

module EquivalenceCases
	module RawSafe
		class RawSafe < Phlex::HTML
			def initialize
				@safe = safe("<i>ivar</i>")
			end

			def view_template
				raw safe("<b>literal</b>")
				raw(safe("<b>parenthesised</b>"))
				raw @safe
				raw safe("<b>#{self.class.name}</b>")
				raw nil
			end
		end
	end
end
