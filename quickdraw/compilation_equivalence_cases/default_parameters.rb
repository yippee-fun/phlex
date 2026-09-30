# frozen_string_literal: true

module EquivalenceCases
	module DefaultParameters
		class DefaultParameters < Phlex::HTML
			def view_template
				part
				part("given")
			end

			def part(path = File.basename(__FILE__), line: __LINE__)
				div { "#{path}:#{line}" }
			end
		end
	end
end
