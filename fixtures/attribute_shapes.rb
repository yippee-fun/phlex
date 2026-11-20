# frozen_string_literal: true

# Each shape passes a value to an element in a way the compiler compiles
# differently. Errors are rescued so partial output is compared too.
class AttributeShapes < Phlex::HTML
	SHAPES = %i[title href src id class style data interpolated interpolated_only interpolated_href splat mixed conditional].freeze

	def initialize(shape, value)
		@shape = shape
		@value = value
	end

	def view_template
		case @shape
		in :title then div(title: @value)
		in :href then a(href: @value)
		in :src then img(src: @value)
		in :id then div(id: @value)
		in :class then div(class: @value)
		in :style then div(style: @value)
		in :data then div(data: @value)
		in :interpolated then div(title: "a #{@value}") { "x" }
		in :interpolated_only then div(title: "#{@value}") { "x" } # rubocop:disable Style/RedundantInterpolation
		in :interpolated_href then a(href: "#{@value}/")
		in :splat then div(**@value)
		in :mixed then a(id: "x", href: @value, class: ["a", @value], data: { value: @value })
		in :conditional then a(href: (@value ? "/yes" : "javascript:no()"), title: (@value ? "yes" : nil))
		end
	rescue => error
		plain "!#{error.class}"
	end
end
