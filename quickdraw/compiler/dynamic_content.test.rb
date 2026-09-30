# frozen_string_literal: true

class DynamicContentCompilerTest < Quickdraw::Test
	test "dynamic content is evaluated once without a block" do
		source = compile_equivalent(<<~RUBY, "<h2>&lt;Title&gt;</h2>")
			def view_template
				@evaluations = 0
				h2 { dynamic_title }
				raise unless @evaluations == 1
			end

			def dynamic_title
				@evaluations += 1
				"<Title>"
			end
		RUBY

		refute source.include?("__yield_content__")
		assert source.include?("bytesize")
		assert source.include?("__implicit_output__")
	end

	test "implicit output is suppressed when the expression writes to the buffer" do
		compile_equivalent(<<~RUBY, "<h2>é</h2>")
			def view_template
				h2 { dynamic_title }
			end

			def dynamic_title
				plain "é"
				"duplicate"
			end
		RUBY
	end

	test "an expression that writes no bytes still has implicit output" do
		compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				h2 { dynamic_title }
			end

			def dynamic_title
				plain ""
				"title"
			end
		RUBY
	end

	["value", "42", "3.14", "42r", "42i", "/title/", "true", "false", "nil", ':"<title>"', '"<title>"', "[]", "{}"].each do |expression|
		test "#{expression} needs no content block or buffer size check" do
			source = compile_equivalent(<<~RUBY)
				def view_template
					value = "<title>"
					h2 { #{expression} }
				end
			RUBY

			refute source.include?("__yield_content__")
			refute source.include?("bytesize")
		end
	end

	test "block local assignments retain their scope" do
		compile_equivalent(<<~RUBY, "<h2>block</h2><h2>method</h2>")
			def view_template
				h2 { value = "block"; value }
				h2 { value }
			end

			def value
				"method"
			end
		RUBY
	end

	test "dynamic locals preserve implicit output formatting" do
		compile_equivalent(<<~RUBY, "<h2><safe></h2><h2>&lt;symbol&gt;</h2><h2>42</h2><h2></h2>")
			def view_template
				[safe("<safe>"), :"<symbol>", 42, nil].each do |value|
					h2 { value }
				end
			end
		RUBY
	end

	test "multi-statement content uses its final value" do
		compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				h2 { 1 + 1; "title" }
			end
		RUBY
	end

	test "captured content uses the capture buffer" do
		compile_equivalent(<<~RUBY, "<h2>&lt;span&gt;title&lt;/span&gt;</h2>")
			def view_template
				h2 { capture { span { "title".dup } } }
			end
		RUBY
	end

	test "implicit begin with rescue and ensure retains its value" do
		source = compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				h2 do
					raise "test"
				rescue
					"title"
				ensure
					@ensured = true
				end
				raise unless @ensured
			end
		RUBY

		refute source.include?("__yield_content__")
	end

	test "nested dynamic content has independent buffer size checks" do
		source = compile_equivalent(<<~RUBY, "<div><h2>title</h2></div>")
			def view_template
				div do
					["title"].each do |value|
						h2 { value.upcase.downcase }
					end
					"duplicate"
				end
			end
		RUBY

		refute source.include?("__yield_content__")
	end

	test "dynamic elements still return nil" do
		compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				raise unless h2 { "title".dup }.nil?
			end
		RUBY
	end

	["next 'title'", "break 'title'", "value = 'title'; value", "redo if false; 'title'"].each do |expression|
		test "#{expression} retains its block boundary" do
			source = compile_equivalent(<<~RUBY)
				def view_template
					h2 { #{expression} }
				end
			RUBY

			assert source.include?("__yield_content__")
		end
	end

	test "block parameters still receive the component" do
		source = compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				h2 { |component| component.dynamic_title }
			end

			def dynamic_title
				"title"
			end
		RUBY

		assert source.include?("__yield_content__")
	end

	test "block arguments retain the runtime fallback" do
		source = compile_equivalent(<<~RUBY, "<h2>title</h2>")
			def view_template
				content = ->(component) { "title" }
				h2(&content)
			end
		RUBY

		assert source.include?("__yield_content__")
	end

	private def compile_equivalent(source, expected = nil)
		component = Class.new(Phlex::HTML)
		component.class_eval(source)
		before = component.new.call
		assert_equal before, expected if expected

		node = Refract::Converter.new.visit(Prism.parse(source).value.statements.body.first)
		compiled = Phlex::Compiler::MethodCompiler.new(component, "/components/test.rb").compile(node)
		formatted = Refract::Formatter.new.format_node(compiled).source
		component.class_eval(formatted)
		assert_equal component.new.call, before
		formatted
	end
end
