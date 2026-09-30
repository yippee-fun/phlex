# frozen_string_literal: true

module EquivalenceCases
	module PlainNilValue
		class PlainNilValue < Phlex::HTML
			def view_template
				values = [1].map { br; "value"; plain nil }
				plain values.inspect
			end
		end
	end
end
