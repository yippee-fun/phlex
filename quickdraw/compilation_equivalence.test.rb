# frozen_string_literal: true

Dir["./compilation_equivalence_cases/*.rb", base: File.dirname(__FILE__)].each do |file|
	test File.basename(file) do
		load File.expand_path(file, File.dirname(__FILE__))

		class_name = File.basename(file, ".rb").split("_").map(&:capitalize).join
		component = Object.const_get(class_name)

		before = component.new.call
		Phlex::Compiler.compile(component)
		after = component.new.call

		assert_equal_html after, before
	end
end
