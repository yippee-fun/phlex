# frozen_string_literal: true

class ElementRegistryTest < Quickdraw::Test
	def new_elements_module
		Module.new { extend Phlex::SGML::Elements }
	end

	test "the built-in registries are frozen" do
		[Phlex::HTML::StandardElements, Phlex::HTML::VoidElements, Phlex::SVG::StandardElements].each do |elements|
			assert elements.__registered_elements__.frozen?
			assert elements.__registered_void_elements__.frozen?
			assert elements.__registered_elements__.each_value.all?(&:frozen?)
		end
	end

	test "a module that has registered nothing has empty registries" do
		elements = new_elements_module

		assert_equal elements.__registered_elements__, {}
		assert_equal elements.__registered_void_elements__, {}
		refute elements.instance_variable_defined?(:@__element_registry__)
	end

	test "registering replaces the registry rather than mutating it" do
		elements = new_elements_module
		elements.register_element :foo_bar
		before = elements.__registered_elements__

		elements.register_element :baz_qux

		assert_equal elements.__registered_elements__, { foo_bar: "foo-bar", baz_qux: "baz-qux" }
		assert elements.__registered_elements__.frozen?
		assert_equal before, { foo_bar: "foo-bar" }
	end

	test "registering a void element updates both registries" do
		elements = new_elements_module
		elements.__register_void_element__ :foo_bar

		assert_equal elements.__registered_elements__, { foo_bar: "foo-bar" }
		assert_equal elements.__registered_void_elements__, { foo_bar: "foo-bar" }
		assert elements.__registered_void_elements__.frozen?
	end

	test "re-registering a void element as standard removes it from the void registry" do
		elements = new_elements_module
		elements.__register_void_element__ :foo_bar

		elements.register_element :foo_bar

		assert_equal elements.__registered_elements__, { foo_bar: "foo-bar" }
		assert_equal elements.__registered_void_elements__, {}
	end

	test "an element's tag and void status are replaced together" do
		elements = new_elements_module
		elements.__register_void_element__ :foo_bar
		before = elements.__element_registry__

		elements.register_element :foo_bar, tag: "new-tag"
		after = elements.__element_registry__

		assert_equal [before.elements, before.void_elements], [{ foo_bar: "foo-bar" }, { foo_bar: "foo-bar" }]
		assert_equal [after.elements, after.void_elements], [{ foo_bar: "new-tag" }, {}]
	end

	test "a re-registration refused before its method is replaced leaves the registry as it was" do
		elements = new_elements_module
		elements.register_element :foo_bar, tag: "old-foo"
		elements.__register_void_element__ :baz_qux, tag: "old-baz"
		elements.define_singleton_method(:method_added) { |name| raise "refused #{name}" }

		assert_raises(RuntimeError) { elements.__register_void_element__ :foo_bar, tag: "new-foo" }
		assert_raises(RuntimeError) { elements.register_element :baz_qux, tag: "new-baz" }

		assert_equal elements.__registered_elements__, { foo_bar: "old-foo", baz_qux: "old-baz" }
		assert_equal elements.__registered_void_elements__, { baz_qux: "old-baz" }
	end

	test "registering never freezes the caller's tag" do
		elements = new_elements_module
		tag = +"my-tag"

		elements.register_element(:my_tag, tag:)
		elements.register_element :other_tag, tag: :"other-tag"

		refute tag.frozen?
		assert_equal elements.__registered_elements__, { my_tag: "my-tag", other_tag: "other-tag" }
	end

	test "registrations racing each other are all recorded" do
		names = Array.new(8) { |index| :"racing_#{index}" }

		50.times do
			elements = new_elements_module
			names.map { |name| Thread.new { elements.register_element(name) } }.each(&:join)

			assert_equal elements.__registered_elements__.keys.sort, names
		end
	end

	test "a component's registry is frozen and separate from its superclass's" do
		parent = Class.new(Phlex::HTML) { register_element :trix_editor }
		child = Class.new(parent) do
			register_element :trix_toolbar

			def view_template = trix_editor { trix_toolbar }
		end

		assert child.__registered_elements__.frozen?
		assert_equal parent.__registered_elements__, { trix_editor: "trix-editor" }
		assert_equal child.__registered_elements__, { trix_toolbar: "trix-toolbar" }
		assert_equal child.call, "<trix-editor><trix-toolbar></trix-toolbar></trix-editor>"
	end

	if defined?(::Ractor)
		test "registries are shareable between Ractors" do
			component = Class.new(Phlex::HTML) { register_element :trix_editor }

			[Phlex::HTML::StandardElements, Phlex::HTML::VoidElements, Phlex::SVG::StandardElements, component, new_elements_module].each do |elements|
				assert Ractor.shareable?(elements.__element_registry__)
			end
		end

		test "a frozen tag carrying unshareable state is copied" do
			tag = +"my-tag"
			tag.instance_variable_set(:@state, +"mutable")
			tag.freeze

			elements = new_elements_module
			elements.register_element(:my_tag, tag:)
			elements.__register_void_element__(:my_void, tag:)

			assert Ractor.shareable?(elements.__element_registry__)
			assert_equal elements.__registered_elements__, { my_tag: "my-tag", my_void: "my-tag" }
		end
	end
end
