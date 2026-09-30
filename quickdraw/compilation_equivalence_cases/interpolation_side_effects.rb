# frozen_string_literal: true

module EquivalenceCases
	module InterpolationSideEffects
		class InterpolationSideEffects < Phlex::HTML
			def view_template
				plain "prefix#{span { 'inner' }}suffix"
				h1 { "Hi #{span { 'x' }}" }
				p { "#{@_state.buffer.bytesize}" }
				div(class: "#{@_state.buffer.bytesize}") { "attr" }
			end
		end
	end
end
