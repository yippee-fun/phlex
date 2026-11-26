# frozen_string_literal: true

class AttributeCacheExpansionTest < Quickdraw::Test
	test "using a component without a source location" do
		refute_raises do
			# Intentionally not passing a source location here.
			eval <<~RUBY
    class Example < Phlex::HTML
    	def view_template
    	end
    end
RUBY
		end
	end

	test "defining view_template from a file expands the attribute cache by its size" do
		path = File.join(tmpdir, "expanding.rb")
		File.write(path, "Class.new(Phlex::HTML) { def other = nil }\nClass.new(Phlex::HTML) { def view_template = nil }\n")
		eval(File.read(path).lines.first, TOPLEVEL_BINDING, path, 1)

		refute Phlex::CACHED_FILES.include?(path)

		calls = spy(Phlex::ATTRIBUTE_CACHE, :expand)
		eval(File.read(path).lines.last, TOPLEVEL_BINDING, path, 2)

		assert Phlex::CACHED_FILES.include?(path)
		assert_equal calls.calls.map(&:args), [[File.size(path)]]
	end

	test "a relative path expands the attribute cache, but an eval's doesn't" do
		calls = spy(Phlex, :__expand_attribute_cache__)

		eval("Class.new(Phlex::HTML) { def view_template = nil }", TOPLEVEL_BINDING, "./relative.rb", 1)
		eval("Class.new(Phlex::HTML) { def view_template = nil }", TOPLEVEL_BINDING, "(irb)", 1)

		assert_equal calls.calls.map(&:args), [["./relative.rb"]]
	end

	test "a method without a source location can be defined" do
		refute_raises do
			Class.new(Phlex::HTML) { define_method(:inspected, Kernel.instance_method(:inspect)) }
		end
	end
end
