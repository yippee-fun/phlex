# frozen_string_literal: true

# test "standard element, no args, no block" do
# 	snippet = Prism.parse(<<~RUBY).value.statements.body.first
# 		def foo
# 			h1
# 		end
# 	RUBY

# 	compiled = Phlex::Compiler::MethodCompiler.new(Phlex::HTML).compile(snippet)

# 	assert_equal_ruby compiled.strip, out = <<~RUBY.strip
# 		def foo
# 			__phlex_buffer__ = @_state.buffer
# 			__phlex_buffer__ << "<h1></h1>"
# 		end
# 	RUBY
# end

test "sequential elements", skip: true do
	snippet = Prism.parse(<<~RUBY).value.statements.body.first
		def foo
			div do
				"Hello"
			end
		end
	RUBY

	compiled = Phlex::Compiler::MethodCompiler.new(Phlex::HTML).compile(snippet)

	puts compiled

	assert_equal compiled.strip, out = <<~RUBY.strip
		def foo
			__phlex_buffer__ = @_state.buffer
			__phlex_buffer__ << "<h1></h1><h2></h2>"
		end
	RUBY
end
