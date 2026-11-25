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
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a number an element's block returns is formatted at compile time" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div { 42 }
				span { -1.5 }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div>42</div><span>-1.5</span>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a number an element's block returns is formatted at runtime when format_object is overridden" do
		component = Class.new(Phlex::HTML) { private def format_object(object) = "n#{object}" }
		node = Refract::Converter.new.visit(Prism.parse("def a = div { 42 }").value).statements.body.first
		environment = Phlex::Compiler::Environment.new(component)
		compiled = Refract::Formatter.new.format_node(Phlex::Compiler::MethodCompiler.new(environment, "/components/test.rb").compile(node)).source

		assert compiled.include?("format_object(")
		refute environment.inlined.include?(:format_object)
	end

	test "a local only assigned a literal is expected to hold it, with the output around it emitted both ways" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				count = 1
				span { "s" }
				div { count }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					count = 1
					if 1.equal?(count)
						(if __phlex_state__.should_render?
							__phlex_state__.buffer.<<("<span>s</span><div>1</div>")
						end
						nil)
					else
						(if __phlex_state__.should_render?
							__phlex_state__.buffer.<<("<span>s</span><div>")
						end
						nil)
						__phlex_done_2__ = false
						begin
							if __phlex_state__.should_render?
								if ::Phlex::SGML::SafeObject.===(count)
									__phlex_state__.append(count.to_s)
								elsif ::String.===(count)
									__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(count))
								elsif ::Symbol.===(count)
									__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(count.name))
								elsif nil.===(count)
									nil
								else
									if (__phlex_formatted_1__ = format_object(count))
										__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_formatted_1__))
									end
								end
							end
							__phlex_done_2__ = true
						ensure
							unless __phlex_done_2__
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
					end
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a local assigned more than once, or named another way, isn't expected to hold anything" do
		["count += 1", "count = 2", "[1].each { |count| }", "count, _ = []", "-> { count ||= 2 }"].each do |other|
			refute compile("def a\n\tcount = 1\n\t#{other}\n\tdiv { count }\nend").include?("equal?")
		end
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
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "dynamic attributes are serialised in a guard that closes the tag on failure, with fast paths for true, nil, false and Strings" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(class: @cls) { "x" }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = @cls
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__phlex_done_4__ = false
							if ::String.===(__phlex_value_1__)
								__phlex_escaped_2__ = (if ((__phlex_value_1__.include?('"') || __phlex_value_1__.include?("<")) || __phlex_value_1__.include?(">"))
									::Phlex::Compiler.escape_value(__phlex_value_1__)
								else
									__phlex_value_1__
								end)
							elsif true.===(__phlex_value_1__)
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = " class"
							elsif __phlex_value_1__
								if ::Symbol.===(__phlex_value_1__)
									__phlex_escaped_2__ = ::Phlex::Compiler.symbol_value(__phlex_value_1__)
								elsif (::Integer.===(__phlex_value_1__) || ::Float.===(__phlex_value_1__))
									__phlex_escaped_2__ = __phlex_value_1__.to_s
								else
									__phlex_escaped_2__ = nil
									__phlex_text_3__ = ::Phlex::SGML::Attributes.attribute(:class, "class", __phlex_value_1__)
								end
							else
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = ""
							end
							__phlex_done_4__ = true
							""
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_4__
						end)
						if __phlex_escaped_2__
							__phlex_state__.buffer.<<(' class="').<<(__phlex_escaped_2__).<<('"')
						else
							__phlex_state__.buffer.<<(__phlex_text_3__)
						end
						__phlex_state__.buffer.<<(">x</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
							__phlex_done_4__ = false
							if ::String.===(__phlex_value_1__)
								__phlex_escaped_2__ = (if ((__phlex_value_1__.include?('"') || __phlex_value_1__.include?("<")) || __phlex_value_1__.include?(">"))
									::Phlex::Compiler.escape_value(__phlex_value_1__)
								else
									__phlex_value_1__
								end)
							elsif true.===(__phlex_value_1__)
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = " id"
							elsif __phlex_value_1__
								if ::Symbol.===(__phlex_value_1__)
									__phlex_escaped_2__ = ::Phlex::Compiler.symbol_value(__phlex_value_1__)
								elsif (::Integer.===(__phlex_value_1__) || ::Float.===(__phlex_value_1__))
									__phlex_escaped_2__ = __phlex_value_1__.to_s
								else
									__phlex_escaped_2__ = nil
									__phlex_text_3__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_1__)
								end
							else
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = ""
							end
							__phlex_done_4__ = true
							""
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_4__
						end)
						if __phlex_escaped_2__
							__phlex_state__.buffer.<<(' id="').<<(__phlex_escaped_2__).<<('"')
						else
							__phlex_state__.buffer.<<(__phlex_text_3__)
						end
						__phlex_state__.buffer.<<(">x</div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
							__phlex_done_6__ = false
							__phlex_attribute_3__ = ::Phlex::SGML::Attributes.reference_attribute(:href, "href", __phlex_value_1__)
							if ::String.===(__phlex_value_2__)
								__phlex_escaped_4__ = (if ((__phlex_value_2__.include?('"') || __phlex_value_2__.include?("<")) || __phlex_value_2__.include?(">"))
									::Phlex::Compiler.escape_value(__phlex_value_2__)
								else
									__phlex_value_2__
								end)
							elsif true.===(__phlex_value_2__)
								__phlex_escaped_4__ = nil
								__phlex_text_5__ = " id"
							elsif __phlex_value_2__
								if ::Symbol.===(__phlex_value_2__)
									__phlex_escaped_4__ = ::Phlex::Compiler.symbol_value(__phlex_value_2__)
								elsif (::Integer.===(__phlex_value_2__) || ::Float.===(__phlex_value_2__))
									__phlex_escaped_4__ = __phlex_value_2__.to_s
								else
									__phlex_escaped_4__ = nil
									__phlex_text_5__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_2__)
								end
							else
								__phlex_escaped_4__ = nil
								__phlex_text_5__ = ""
							end
							__phlex_done_6__ = true
							__phlex_attribute_3__
						ensure
							__phlex_state__.buffer.<<(">") unless __phlex_done_6__
						end).<<(' class="x"')
						if __phlex_escaped_4__
							__phlex_state__.buffer.<<(' id="').<<(__phlex_escaped_4__).<<('"')
						else
							__phlex_state__.buffer.<<(__phlex_text_5__)
						end
						__phlex_state__.buffer.<<(">x</a>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
							__phlex_done_5__ = false
							if ::String.===(__phlex_value_2__)
								__phlex_escaped_3__ = (if ((__phlex_value_2__.include?('"') || __phlex_value_2__.include?("<")) || __phlex_value_2__.include?(">"))
									::Phlex::Compiler.escape_value(__phlex_value_2__)
								else
									__phlex_value_2__
								end)
							elsif true.===(__phlex_value_2__)
								__phlex_escaped_3__ = nil
								__phlex_text_4__ = " id"
							elsif __phlex_value_2__
								if ::Symbol.===(__phlex_value_2__)
									__phlex_escaped_3__ = ::Phlex::Compiler.symbol_value(__phlex_value_2__)
								elsif (::Integer.===(__phlex_value_2__) || ::Float.===(__phlex_value_2__))
									__phlex_escaped_3__ = __phlex_value_2__.to_s
								else
									__phlex_escaped_3__ = nil
									__phlex_text_4__ = ::Phlex::SGML::Attributes.attribute(:id, "id", __phlex_value_2__)
								end
							else
								__phlex_escaped_3__ = nil
								__phlex_text_4__ = ""
							end
							__phlex_done_5__ = true
							__phlex_value_1__
						ensure
							__phlex_state__.buffer.<<("></div>") unless __phlex_done_5__
						end)
						if __phlex_escaped_3__
							__phlex_state__.buffer.<<(' id="').<<(__phlex_escaped_3__).<<('"')
						else
							__phlex_state__.buffer.<<(__phlex_text_4__)
						end
						__phlex_state__.buffer.<<("></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a literal hash nested in a nested attribute hash is serialised entry by entry" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(data: { card: { id: @id, open: true } })
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = @id
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(begin
							__phlex_done_4__ = false
							if ::String.===(__phlex_value_1__)
								__phlex_escaped_2__ = (if ((__phlex_value_1__.include?('"') || __phlex_value_1__.include?("<")) || __phlex_value_1__.include?(">"))
									::Phlex::Compiler.escape_value(__phlex_value_1__)
								else
									__phlex_value_1__
								end)
							elsif true.===(__phlex_value_1__)
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = " data-card-id"
							elsif __phlex_value_1__
								if ::Symbol.===(__phlex_value_1__)
									__phlex_escaped_2__ = ::Phlex::Compiler.symbol_value(__phlex_value_1__)
								elsif (::Integer.===(__phlex_value_1__) || ::Float.===(__phlex_value_1__))
									__phlex_escaped_2__ = __phlex_value_1__.to_s
								else
									__phlex_escaped_2__ = nil
									__phlex_text_3__ = ::Phlex::Compiler.nested_attributes(:id, __phlex_value_1__, "data-card-")
								end
							else
								__phlex_escaped_2__ = nil
								__phlex_text_3__ = ""
							end
							__phlex_done_4__ = true
							""
						ensure
							__phlex_state__.buffer.<<("></div>") unless __phlex_done_4__
						end)
						if __phlex_escaped_2__
							__phlex_state__.buffer.<<(' data-card-id="').<<(__phlex_escaped_2__).<<('"')
						else
							__phlex_state__.buffer.<<(__phlex_text_3__)
						end
						__phlex_state__.buffer.<<(" data-card-open></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "a token chosen with && is serialised per branch, like one chosen with if" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div(class: ["card", (@active && "active")])
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					__phlex_value_1__ = if @active
						true
					else
						false
					end
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div").<<(if __phlex_value_1__
							' class="card active"'
						else
							' class="card"'
						end).<<("></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "elements called on the parameter an element yields itself to are inlined" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div { |d| d.span { "x" }; d.br }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div><span>x</span><br></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "whitespace with dynamic content is inlined and evaluated when not rendering" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				whitespace { @text }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<(" ")
					end
					nil)
					__implicit_output__(@text)
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<(" ")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "dynamic content inlines the output size check and closes the tag on any exit" do
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
						__phlex_content_length_1__ = __phlex_state__.output_bytesize
						__phlex_content_2__ = (helper)
						if __phlex_content_length_1__.==(__phlex_state__.output_bytesize)
							if __phlex_state__.should_render?
								if ::Phlex::SGML::SafeObject.===(__phlex_content_2__)
									__phlex_state__.append(__phlex_content_2__.to_s)
								elsif ::String.===(__phlex_content_2__)
									__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_content_2__))
								elsif ::Symbol.===(__phlex_content_2__)
									__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_content_2__.name))
								elsif nil.===(__phlex_content_2__)
									nil
								else
									if (__phlex_formatted_3__ = format_object(__phlex_content_2__))
										__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_formatted_3__))
									end
								end
							end
						end
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
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
						__phlex_state__.buffer.<<("<html><head><title>T</title></head>")
					end
					nil)
					__phlex_done_1__ = false
					begin
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
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
				end
			end
		RUBY
	end

	test "nested elements share one guard, with the ASCII text around their content fused" do
		assert_equal compile(<<~RUBY), <<~RUBY
			def a
				div { h3 { @title }; p { "x" } }
			end
		RUBY
			def a
				begin
					__phlex_state__ = @_state
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("<div><h3>")
					end
					nil)
					__phlex_done_2__ = false
					begin
						if __phlex_state__.should_render?
							if ::Phlex::SGML::SafeObject.===(@title)
								__phlex_state__.append(@title.to_s)
							elsif ::String.===(@title)
								__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(@title))
							elsif ::Symbol.===(@title)
								__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(@title.name))
							elsif nil.===(@title)
								nil
							else
								if (__phlex_formatted_1__ = format_object(@title))
									__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_formatted_1__))
								end
							end
						end
						__phlex_done_2__ = true
					ensure
						unless __phlex_done_2__
							(if __phlex_state__.should_render?
								__phlex_state__.buffer.<<("</h3></div>")
							end
							nil)
						end
					end
					(if __phlex_state__.should_render?
						__phlex_state__.buffer.<<("</h3><p>x</p></div>")
					end
					nil)
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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
					__phlex_self__ = self
					@items.each { |i|
						begin
							if __phlex_self__.__phlex_equal__?(self)
								__phlex_state__ = @_state
								(if __phlex_state__.should_render?
									__phlex_state__.buffer.<<("<li>")
								end
								nil)
								__phlex_done_2__ = false
								begin
									if __phlex_state__.should_render?
										if ::Phlex::SGML::SafeObject.===(i)
											__phlex_state__.append(i.to_s)
										elsif ::String.===(i)
											__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(i))
										elsif ::Symbol.===(i)
											__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(i.name))
										elsif nil.===(i)
											nil
										else
											if (__phlex_formatted_1__ = format_object(i))
												__phlex_state__.buffer.<<(::Phlex::Escape.html_escape(__phlex_formatted_1__))
											end
										end
									end
									__phlex_done_2__ = true
								ensure
									unless __phlex_done_2__
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
						rescue ::Exception => __phlex_exception__
							::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
						end
					}
				rescue ::Exception => __phlex_exception__
					::Kernel.raise(::Phlex.__map_exception__(__phlex_exception__))
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

	test "a kit named after its component was added keeps calling the kit" do
		kit = Module.new { extend Phlex::Kit }
		kit.const_set(:Card, Class.new(Phlex::HTML))
		Object.const_set(:CompilerTestLateKit, kit)
		component = Class.new(Phlex::HTML) { include kit }

		node = Refract::Converter.new.visit(Prism.parse(<<~RUBY).value).statements.body.first
			def a
				Card("Title")
			end
		RUBY

		compiled = Phlex::Compiler::MethodCompiler.new(Phlex::Compiler::Environment.new(component), "/components/test.rb").compile(node)

		assert_equal compiled, nil
	ensure
		Object.__send__(:remove_const, :CompilerTestLateKit)
	end

	test "a kit's component is rendered directly" do
		kit = Object.const_set(:CompilerTestKit, Module.new { extend Phlex::Kit })
		kit.const_set(:Card, Class.new(Phlex::HTML))
		component = Class.new(Phlex::HTML) { include kit }

		node = Refract::Converter.new.visit(Prism.parse(<<~RUBY).value).statements.body.first
			def a
				Card("Title") { "content" }
			end
		RUBY

		compiled = Phlex::Compiler::MethodCompiler.new(Phlex::Compiler::Environment.new(component), "/components/test.rb").compile(node)
		source = Refract::Formatter.new.format_node(compiled).source

		assert source.include?('render(::Object.const_get(:CompilerTestKit).const_get(:Card).new("Title")) {')
		refute source.include?("Card(")
	ensure
		Object.__send__(:remove_const, :CompilerTestKit)
	end

	test "methods with nothing to compile are left alone" do
		assert_equal compile(<<~RUBY), nil
			def a
				x = 1
			end
		RUBY
	end
end
