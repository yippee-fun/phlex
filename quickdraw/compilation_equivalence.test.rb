# frozen_string_literal: true

class CompilationEquivalenceTest < Quickdraw::Test
	Dir["./compilation_equivalence_cases/*.rb", base: File.dirname(__FILE__)].each do |file|
		test File.basename(file) do
			load File.expand_path(file, File.dirname(__FILE__))

			class_name = File.basename(file, ".rb").split("_").map(&:capitalize).join
			component = Object.const_get(class_name)

			before = component.new.call
			Phlex::Compiler.compile(component)
			after = component.new.call

			assert_equal after, before
		end
	end

	require_relative "../fixtures/page"
	require_relative "../fixtures/layout"

	test "benchmark fixtures" do
		before = Example::Page.new.call
		Phlex::Compiler.compile(Example::LayoutComponent)
		Phlex::Compiler.compile(Example::Page)
		after = Example::Page.new.call

		assert_equal after, before
	end
end
