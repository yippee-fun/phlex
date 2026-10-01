# frozen_string_literal: true

# Snapshots of the code the compiler generates for a method, so changes to the
# shape of the output are reviewed deliberately.
class CompilerTest < Quickdraw::Test
	Phlex::Compiler

	# A fresh class, so subclasses defined by other tests can't affect what gets inlined.
	COMPONENT = Class.new(Phlex::HTML)

	def compile(source)
		node = Refract::Converter.new.visit(Prism.parse(source).value).statements.body.first
		compiled = Phlex::Compiler::MethodCompiler.new(Phlex::Compiler::Environment.new(COMPONENT), "/components/test.rb").compile(node)
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
							__phlex_done_2__ = false
							__phlex_attribute_1__ = ::Phlex::SGML::Attributes.attribute(:class, "class", @cls)
							__phlex_done_2__ = true
							__phlex_attribute_1__
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_2__
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
					__phlex_value_1__ = dom_id
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__phlex_done_3__ = false
							__phlex_attribute_2__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_1__)
							__phlex_done_3__ = true
							__phlex_attribute_2__
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_3__
						end).<<(">x</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "static and dynamic attributes serialise piece by piece, evaluating every dynamic one before any is appended" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				a(href: @url, class: "x", id: dom_id) { "x" }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = @url
					__phlex_value_2__ = dom_id
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<a").<<(begin
							__phlex_done_5__ = false
							__phlex_attribute_3__ = ::Phlex::SGML::Attributes.reference_attribute(:href, "href", __phlex_value_1__)
							__phlex_attribute_4__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_2__)
							__phlex_done_5__ = true
							__phlex_attribute_3__
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_5__
						end).<<(' class="x"').<<(__phlex_attribute_4__).<<(">x</a>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a conditional over literal attribute values is serialised per branch, and every value is read before any is serialised" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(class: active? ? "on" : nil, id: @id)
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = if active?
						' class="on"'
					else
						""
					end
					__phlex_value_2__ = @id
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__phlex_done_4__ = false
							__phlex_attribute_3__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_2__)
							__phlex_done_4__ = true
							__phlex_value_1__
						ensure
							__phlex_state__.buffer.<<("></div>") unless __phlex_done_4__
						end).<<(__phlex_attribute_3__).<<("></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a conditional over literal content fuses into the append" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				span { @active ? "<on>" : "off" }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<span>").<<(if @active
							"&lt;on&gt;"
						else
							"off"
						end).<<("</span>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "whitespace with dynamic content is inlined behind the runtime's render check" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				whitespace { @text }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					if __phlex_state__.should_render?
						(if __phlex_state__.should_render?
							__phlex_state__.buffer.<<(" ")
						end
						nil)
						__implicit_output__(@text)
						(if __phlex_state__.should_render?
							__phlex_state__.buffer.<<(" ")
						end
						nil)
					end
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "dynamic content inlines the buffer check and closes the tag on any exit" do
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
					__phlex_done_4__ = false
					begin
						__phlex_content_buffer_1__ = __phlex_state__.buffer
						__phlex_content_length_2__ = __phlex_content_buffer_1__.bytesize
						__phlex_content_3__ = (helper)
						__implicit_output__(__phlex_content_3__) if __phlex_content_length_2__.==(__phlex_content_buffer_1__.bytesize)
						__phlex_done_4__ = true
					ensure
						unless __phlex_done_4__
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

	test "calls in blocks nested more than four deep are left alone, and every copy of a block sees the real __FILE__" do
		source = compile(<<~RUBY)
			def a
				div { "top" }
				one { two { three { four { span { "four" }; five { p { __FILE__ } } } } } }
			end
		RUBY

		assert source.include?("<div>top</div>")
		assert source.include?("<span>four</span>")
		refute source.include?("<p>")
		refute source.include?("__FILE__")
		assert_equal source.scan('"/components/test.rb"').size, 5
	end

	test "lambdas preserve __FILE__ without compiling their element or helper calls" do
		source = compile(<<~RUBY)
			def a
				div { "top" }
				->(path = __FILE__) { span { __FILE__ }; plain "text"; -> { __FILE__ } }
				->(path: __FILE__) { path }
			end
		RUBY

		assert source.include?("<div>top</div>")
		refute source.include?("<span>")
		assert source.include?('plain("text")')
		refute source.include?("__FILE__")
		assert_equal source.scan('"/components/test.rb"').size, 4
	end

	test "methods with nothing to compile are left alone" do
		assert_equal compile(<<~RUBY), nil
			def a
				x = 1
			end
		RUBY
	end
end
