# frozen_string_literal: true

module EquivalenceCases
	module BlockValues
		class BlockValues < Phlex::HTML
			def initialize
				@ivar = "ivar<>"
			end

			def str = "meth<>"

			def view_template
				div { 42 }
				div { 4.2 }
				div { :sym }
				div { nil }
				div { str }
				div { @ivar }
				div { safe("<b>x</b>") }
				div { span { "a" }; "ignored" }
				div { part; "ignored" }
				div { "a<b" }
				div { "x".b }
				div { "#{span { 'x' }}" } # rubocop:disable Style/RedundantInterpolation
			end

			def part
				span { "part" }
			end
		end

		class ObjectValue < Phlex::HTML
			def view_template
				div { Object.new }
			end
		end

		class ArrayValue < Phlex::HTML
			def view_template
				div { [1, 2] }
			end
		end
	end
end
