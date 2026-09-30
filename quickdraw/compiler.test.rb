# frozen_string_literal: true

# Snapshots of the code the compiler generates for a method, so changes to the
# shape of the output are reviewed deliberately.
class CompilerTest < Quickdraw::Test
	Phlex::Compiler

	# A fresh class, so subclasses defined by other tests can't affect what gets inlined.
	COMPONENT = Class.new(Phlex::HTML)

	def compile(source)
		node = Refract::Converter.new.visit(Prism.parse(source).value).statements.body.first
		compiled = Phlex::Compiler::MethodCompiler.new(COMPONENT, "/components/test.rb").compile(node)
		compiled && "#{Refract::Formatter.new.format_node(compiled).source}\n"
	end

	test "static elements fuse into one append" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				h1 { "Hello" }
				br
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<h1>Hello</h1><br>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "literal plain is escaped at compile time" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				plain "<b>"
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("&lt;b&gt;")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "pure dynamic attributes are appended in the chain and close the tag on failure" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(class: @cls) { "x" }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__attributes__({
								class: @cls
							})
						rescue ::Exception
							__phlex_state__.buffer.<<(">")
							raise()
						end).<<(">x</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "impure attribute values are evaluated before the element opens" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(id: dom_id) { "x" }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = {
						id: dom_id
					}
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__attributes__(__phlex_value_1__)
						rescue ::Exception
							__phlex_state__.buffer.<<(">")
							raise()
						end).<<(">x</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "dynamic content keeps the runtime yield and closes the tag on any exit" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div { helper }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div>")
					end
					nil)
					__phlex_done_1__ = false
					begin
						__yield_content__ {
							helper
						}
						__phlex_done_1__ = true
					ensure
						unless __phlex_done_1__
							(if __phlex_state__.should_render?
								__phlex_state__.buffer.<<("</div>")
							end
							nil)
						end
					end
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "head flushes after closing" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				html { head { title { "T" } } }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<html>")
					end
					nil)
					__phlex_done_1__ = false
					begin
						(if __phlex_state__.should_render?
							__phlex_state__.buffer.<<("<head><title>T</title></head>")
						end
						nil)
						flush() if __phlex_state__.should_render?
						__phlex_done_1__ = true
					ensure
						unless __phlex_done_1__
							(if __phlex_state__.should_render?
								__phlex_state__.buffer.<<("</html>")
							end
							nil)
						end
					end
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("</html>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "blocks passed to unknown methods are compiled behind a self check" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				@items.each { |i| li { i } }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_self__ = self
					@items.each { |i|
						if self.equal?(__phlex_self__)
							(if __phlex_state__.should_render?
								__phlex_state__.buffer.<<("<li>")
							end
							nil)
							__phlex_done_1__ = false
							begin
								__implicit_output__(i)
								__phlex_done_1__ = true
							ensure
								unless __phlex_done_1__
									(if __phlex_state__.should_render?
										__phlex_state__.buffer.<<("</li>")
									end
									nil)
								end
							end
							(if __phlex_state__.should_render?
								__phlex_state__.buffer.<<("</li>")
							end
							nil)
						else
							li {
								i
							}
						end
					}
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "methods with nothing to compile are left alone" do
		assert_equal compile(<<~RUBY), nil
			def a
				x = 1
			end
		RUBY
	end
end
