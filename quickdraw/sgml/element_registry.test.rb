# frozen_string_literal: true

class ElementRegistryTest < Quickdraw::Test
	BUILT_INS = [
		Phlex::HTML::StandardElements,
		Phlex::HTML::VoidElements,
		Phlex::SVG::StandardElements,
	].freeze

	def new_elements_module
		Module.new { extend Phlex::SGML::Elements }
	end

	test "the built-in registries are frozen once their elements are registered" do
		BUILT_INS.each do |elements|
			assert elements.__registered_elements__.frozen?
			assert elements.__registered_void_elements__.frozen?
			assert elements.__registered_elements__.each_value.all?(&:frozen?)
		end
	end

	test "registering after the freeze replaces the registry with a frozen copy" do
		elements = new_elements_module
		elements.register_element :foo_bar
		elements.__freeze_registries__
		before = elements.__registered_elements__

		elements.register_element :baz_qux

		assert_equal elements.__registered_elements__, { foo_bar: "foo-bar", baz_qux: "baz-qux" }
		assert elements.__registered_elements__.frozen?
		assert_equal before, { foo_bar: "foo-bar" }
		assert before.frozen?
	end

	test "registering a void element after the freeze updates both registries" do
		elements = new_elements_module
		elements.__register_void_element__ :foo_bar
		elements.__freeze_registries__

		elements.__register_void_element__ :baz_qux

		assert_equal elements.__registered_elements__, { foo_bar: "foo-bar", baz_qux: "baz-qux" }
		assert_equal elements.__registered_void_elements__, { foo_bar: "foo-bar", baz_qux: "baz-qux" }
		assert elements.__registered_void_elements__.frozen?
	end

	test "re-registering a void element as standard after the freeze removes it from the void registry" do
		elements = new_elements_module
		elements.__register_void_element__ :foo_bar
		elements.__freeze_registries__

		elements.register_element :foo_bar

		assert_equal elements.__registered_void_elements__, {}
		assert elements.__registered_void_elements__.frozen?
	end

	test "registering after the freeze never freezes the caller's tag" do
		elements = new_elements_module
		elements.__freeze_registries__
		tag = +"my-tag"

		elements.register_element(:my_tag, tag:)
		elements.register_element :other_tag, tag: :"other-tag"

		refute tag.frozen?
		assert_equal elements.__registered_elements__, { my_tag: "my-tag", other_tag: "other-tag" }
	end

	if defined?(::Ractor)
		test "registries stay shareable after a registration that follows the freeze" do
			elements = new_elements_module
			elements.register_element :foo_bar
			elements.__freeze_registries__
			elements.register_element :baz_qux

			assert Ractor.shareable?(elements.__registered_elements__)
			assert Ractor.shareable?(elements.__registered_void_elements__)
		end
	end

	test "a component's own registry stays mutable" do
		component = Class.new(Phlex::HTML) do
			register_element :trix_editor

			def view_template = trix_editor { "Hello" }
		end

		refute component.__registered_elements__.frozen?
		assert_equal component.__registered_elements__, { trix_editor: "trix-editor" }
		assert_equal component.call, "<trix-editor>Hello</trix-editor>"
	end
end
