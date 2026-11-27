# frozen_string_literal: true

require "attribute_generators"
require "attribute_shapes"

class CompilationEquivalencePropertiesTest < Quickdraw::Test
	include AttributeGenerators

	Interpreted = AttributeShapes.dup.tap { |klass| klass.compile false }

	def setup
		Phlex::Compiler.compile(AttributeShapes)
	end

	fuzz "compiled attributes render as the interpreter renders them", one_of(*AttributeShapes::SHAPES), one_of(VALUE, ATTRIBUTES, ENCODED_TEXT) do |shape, value|
		assert_equal render(AttributeShapes, shape, value), render(Interpreted, shape, value)
	end

	test "the shapes are compiled" do
		assert Phlex::Compiler.compiled?(AttributeShapes)
		refute_equal AttributeShapes.instance_method(:view_template).source_location, Interpreted.instance_method(:view_template).source_location
	end

	private def render(component, shape, value)
		[:returned, component.new(shape, value).call]
	rescue => error
		# Messages can include an object's address, which differs between renders.
		[:raised, error.class, error.message.gsub(/0x\h+/, "0x")]
	end
end
