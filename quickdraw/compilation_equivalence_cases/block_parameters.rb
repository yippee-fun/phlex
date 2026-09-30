# frozen_string_literal: true

module EquivalenceCases
	module BlockParameters
		class BlockParameters < Phlex::HTML
			def view_template
				x = "outside"
				div { |;x| x = "inside"; plain x } # rubocop:disable Layout/SpaceAfterSemicolon, Layout/SpaceAroundBlockParameters
				div { x }
				div { |d| plain d.equal?(self).to_s }
				div { |d| d.span { "via parameter" } }
			end
		end
	end
end
