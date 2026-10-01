# frozen_string_literal: true

module EquivalenceCases
	module LexicalClassPathHolder
	end

	module LexicalClassPath
		# `LexicalClassPathHolder` resolves lexically to the one in
		# EquivalenceCases, not to EquivalenceCases::LexicalClassPath::LexicalClassPathHolder.
		class LexicalClassPathHolder::Component < Phlex::HTML
			def view_template
				div { "lexical" }
			end
		end
	end
end
