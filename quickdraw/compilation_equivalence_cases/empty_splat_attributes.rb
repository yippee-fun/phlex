# frozen_string_literal: true

# A method that forwards `**attributes` to an element, called both with and
# without attributes.
#
# Ruby turns non-empty keyword arguments into a positional Hash when the callee
# declares no keyword parameter, so `__render_attributes__(**attributes)` — what
# the compiler generates — works as long as something is passed. An empty splat
# passes nothing at all, and the compiled method raises `ArgumentError: wrong
# number of arguments (given 0, expected 1)` where the interpreted one renders
# `<pre>`. Any component whose helper forwards attributes is affected.
class EmptySplatAttributes < Phlex::HTML
	# The wrapping `div` is what gets `view_template` itself compiled: a method
	# that only calls other methods is left alone, and `assert_compiled` would
	# report the case as skipped.
	def view_template
		div do
			wrapped("without attributes")
			wrapped("with attributes", style: "margin: 0;")
		end
	end

	def wrapped(text, **attributes)
		pre(**attributes) { plain text }
	end
end
