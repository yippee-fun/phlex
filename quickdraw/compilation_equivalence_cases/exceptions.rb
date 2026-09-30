# frozen_string_literal: true

module EquivalenceCases
	module Exceptions
		class InBlock < Phlex::HTML
			def view_template
				div do
					span { "ok" }
					raise "boom"
				end
			end
		end

		class InHelper < Phlex::HTML
			def view_template
				div { helper }
			end

			def helper
				p { "x" }
				nil.foo
			end
		end

		class InInterpolation < Phlex::HTML
			def boom = raise("interp boom")

			def view_template
				div { "one" }
				div { "two" }
				h1 { "Hello #{boom}" }
				div { "three" }
			end
		end

		class InAttribute < Phlex::HTML
			def boom = raise("attr boom")

			def view_template
				div { "one" }
				div { "two" }
				div(class: boom) { "x" }
			end
		end

		class InBlockValue < Phlex::HTML
			def boom = raise("yield boom")

			def view_template
				div { "one" }
				div { "two" }
				div { boom }
			end
		end

		class InUncompiledHelper < Phlex::HTML
			def view_template
				div { "one" }
				helper
			end

			def helper
				raise "helper boom"
			end
		end
	end
end
