# frozen_string_literal: true

module EquivalenceCases
	module CopiedMethod
		module Template
			def heading = h1 { "copied" }
		end

		# `heading` is copied from Template, whose definition it shares, so it's
		# left alone while the component's own method compiles.
		class CopiedMethod < Phlex::HTML
			define_method(:heading, Template.instance_method(:heading))

			def view_template
				heading
				div { "own" }
			end
		end
	end
end
