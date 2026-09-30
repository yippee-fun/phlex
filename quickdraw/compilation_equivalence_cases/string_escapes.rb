# frozen_string_literal: true

module EquivalenceCases
	module StringEscapes
		class Quotes < Phlex::HTML
			def view_template
				div { 'a "quoted" \\ back\slash' }
				div { "tab\there\nnewline" }
				div(title: 'q"uo\\te') { "x" }
			end
		end

		class HashCurly < Phlex::HTML
			def view_template
				div { 'lit #{x}' } # rubocop:disable Lint/InterpolationCheck
			end
		end

		class HashAt < Phlex::HTML
			def view_template
				div { 'lit #@x and #$y' }
			end
		end

		class Attribute < Phlex::HTML
			def view_template
				div(title: 'a#{b}') { "x" } # rubocop:disable Lint/InterpolationCheck
			end
		end

		class PlainText < Phlex::HTML
			def view_template
				plain 'p #{x}' # rubocop:disable Lint/InterpolationCheck
			end
		end

		class SingleQuoted < Phlex::HTML
			def view_template
				pre { 'single quoted #{not}' }
			end
		end
	end
end
