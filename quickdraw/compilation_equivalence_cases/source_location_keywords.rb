# frozen_string_literal: true

module EquivalenceCases
	module SourceLocationKeywords
		class SourceLocationKeywords < Phlex::HTML
			def view_template
				div { File.basename(__FILE__) }
				div { __LINE__.to_s }
				div { File.basename(__dir__) }
				plain "#{File.basename(__FILE__)}:#{__LINE__}"
			end
		end
	end
end
