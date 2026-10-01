# frozen_string_literal: true

module EquivalenceCases
	module PrependedNamespace
		class View < Phlex::HTML
			def view_template = part

			def div(**, &) = plain("custom")
		end

		# Prepending puts this module before the namespace in its ancestors, but
		# `PrependedNamespace::View` still names the namespace's own View.
		module Prepended
			class View < PrependedNamespace::View
				register_element :div
			end
		end

		prepend Prepended
	end

	class PrependedNamespace::View
		def part = div { "body" }
	end
end
