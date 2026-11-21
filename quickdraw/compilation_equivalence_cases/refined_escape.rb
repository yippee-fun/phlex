# frozen_string_literal: true

module EquivalenceCases
	module RefinedEscape
		module LocalEscape
			refine(Phlex::Escape.singleton_class) { def html_escape(_value) = "refined" }
		end
	end
end

using EquivalenceCases::RefinedEscape::LocalEscape

module EquivalenceCases
	module RefinedEscape
		class RefinedEscape < Phlex::HTML
			def view_template
				text = "<"
				div { text }
			end
		end
	end
end
