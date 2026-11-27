# frozen_string_literal: true

# Compiled blocks call __phlex_equal__? to tell their component from another
# receiver, so a component can't define it in any way.
class ReservedMethodsTest < Quickdraw::Test
	Identity = Module.new { def __phlex_equal__?(_) = true }

	test "a component can't define __phlex_equal__?" do
		component = Class.new(Phlex::HTML)
		error = assert_raises(Phlex::NameError) { component.define_method(:__phlex_equal__?) { |_| true } }
		assert_equal error.message, "__phlex_equal__? is reserved for compiled blocks, so it can't be defined on #{component.inspect}."

		assert_raises(Phlex::NameError) { Class.new(Phlex::HTML) { def __phlex_equal__?(_) = true } }
		assert_raises(Phlex::NameError) { Class.new(Phlex::HTML) { define_method(:__phlex_equal__?) { |_| true } } }
	end

	test "a component can't mix in __phlex_equal__?" do
		assert_raises(Phlex::NameError) { Class.new(Phlex::HTML) { include Identity } }
		assert_raises(Phlex::NameError) { Class.new(Phlex::HTML) { prepend Identity } }
	end

	test "a component instance can't define __phlex_equal__?" do
		assert_raises(Phlex::NameError) { Phlex::HTML.new.extend(Identity) }
		assert_raises(Phlex::NameError) { Phlex::HTML.new.define_singleton_method(:__phlex_equal__?) { |_| true } }
	end
end
