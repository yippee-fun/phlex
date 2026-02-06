# frozen_string_literal: true

require "phlex"

if Phlex::HTML.instance_methods.include?(:tag) && Phlex::SVG.instance_methods.include?(:tag)
	class HTMLComponent < Phlex::HTML
		def initialize(tag, **attributes)
			@tag = tag
			@attributes = attributes
		end

		def view_template(&block)
			tag(@tag, **@attributes, &block)
		end
	end

	class SVGComponent < Phlex::SVG
		def initialize(tag, **attributes)
			@tag = tag
			@attributes = attributes
		end

		def view_template(&block)
			tag(@tag, **@attributes, &block)
		end
	end

	test "with unsafe custom tag name containing a space" do
		error = assert_raises ArgumentError do
			HTMLComponent.call(:"x-widget onclick=alert(1)")
		end

		assert_equal error.message, "Invalid HTML tag: x-widget onclick=alert(1)"
	end

	test "with unsafe custom tag name containing special characters" do
		error = assert_raises ArgumentError do
			HTMLComponent.call(:"x-widget>")
		end

		assert_equal error.message, "Invalid HTML tag: x-widget>"
	end

	test "with unsafe SVG custom tag name containing a space" do
		error = assert_raises ArgumentError do
			SVGComponent.call(:"x-widget onclick=alert(1)")
		end

		assert_equal error.message, "Invalid SVG tag: x-widget onclick=alert(1)"
	end
else
	test "tag API does not exist on this branch" do
		assert !Phlex::HTML.instance_methods.include?(:tag)
		assert !Phlex::SVG.instance_methods.include?(:tag)
	end
end
