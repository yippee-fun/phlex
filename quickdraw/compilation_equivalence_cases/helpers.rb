# frozen_string_literal: true

module EquivalenceCases
	module Helpers
		class Helpers < Phlex::HTML
			def initialize
				@dynamic = "dyn<>"
			end

			def view_template
				doctype
				plain "text<>"
				plain @dynamic
				plain 42
				whitespace
				whitespace { span { "x" } }
				comment { "hi" }
				comment { span { "el" } }
				raw safe("<x>")
				raw nil
				div { raw(nil); "fallback" }
			end
		end

		class Mix < Phlex::HTML
			def initialize
				@symbol = :baz_qux
			end

			def view_template
				div(**mix({ class: "foo_bar" }, { class: @symbol }))
				div(**mix({ class: :foo_bar }, { class: [@symbol] }))
				div(**mix({ class: Set[:foo_bar] }, { class: @symbol }))
			end
		end

		class RawUnsafe < Phlex::HTML
			def view_template
				div { raw "unsafe" }
			end
		end

		class PlainObject < Phlex::HTML
			def view_template
				plain Object.new
			end
		end
	end
end
