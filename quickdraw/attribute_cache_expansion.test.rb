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
end
