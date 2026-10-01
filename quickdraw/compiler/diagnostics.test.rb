# frozen_string_literal: true

require "tmpdir"

class CompilerDiagnosticsTest < Quickdraw::Test
	Phlex::Compiler

	SOURCE = <<~RUBY
		# frozen_string_literal: true
		module DiagnosticsCase
			class Component < Phlex::HTML
				def view_template
					div(&content)
					div("positional")
					br { "content" }
					div(**@attrs) { "x" }
					img(srcset: @srcset)
					div("bad name": 1)
					ul { |list| li }
					plain title
					raw title
					whitespace(1)
					comment { |c| plain "x" }
					doctype(1)
					fragment(:a, &content)
					fragment(:b) { div }
					section { "fine" }
				end

				def content = proc { "x" }
				def title = "t"

				def twice = div { "live" }; def twice = div { "never" }

				def reserved
					__phlex_x__ = 1
					div { __phlex_x__.to_s }
				end

				def defaulted(text = (hr; "default"))
					div { text }
				end
			end

			class self::Dynamic < Phlex::HTML
				def view_template = div
			end
		end
	RUBY

	test "a file edited since it was loaded is reported rather than compiled from the wrong lines" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "edited.rb")
			File.write(path, <<~RUBY)
				class EditedCase < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			load path

			File.write(path, <<~RUBY)
				# A comment added after loading moves every definition down a line.
				class EditedCase < Phlex::HTML
					def view_template = div { "x" }
					def added = span { "y" }
				end
			RUBY

			assert_equal Phlex::Compiler.explain(EditedCase).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"3: view_template isn't compiled because no live method is defined at this line, so the file may have changed since it was loaded",
			]

			Phlex::Compiler.compile(EditedCase)
			refute Phlex::Compiler::MAP.key?(EditedCase.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :EditedCase)
		end
	end

	test "explain lists every call and method left to the runtime, with a reason" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "component.rb")
			File.write(path, SOURCE)
			load path

			diagnostics = Phlex::Compiler.explain(DiagnosticsCase::Component)

			assert_equal diagnostics.map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"5: div keeps its call because its block is forwarded",
				"6: div keeps its call because it has positional arguments",
				"7: br keeps its call because it's a void element given a block",
				"8: div's attributes are serialised together because a key is splatted or isn't a literal",
				"9: img's attributes are serialised together because srcset is rewritten by the element's attribute normaliser",
				"10: div's attributes are serialised at runtime because serialising them now raised Phlex::ArgumentError: Unsafe attribute name detected: bad name.",
				"11: ul's block is yielded at runtime because it has parameters or contains a return, break, next or local assignment",
				"12: plain keeps its call because its argument isn't a literal or an interpolation of literals and variables",
				"13: raw keeps its call because its argument isn't safe with a string literal",
				"14: whitespace keeps its call because it has arguments",
				"15: comment keeps its call because its block is forwarded or it has parameters or contains a return, break, next or local assignment",
				"16: doctype keeps its call because it has arguments or a block",
				"17: fragment keeps its call because its block has parameters or is forwarded",
				"25: twice isn't compiled because it's defined more than once on this line",
				"27: reserved isn't compiled because it uses a local that starts with __phlex_",
				"32: hr keeps its call because it's in a parameter default",
			]

			assert diagnostics.all? { |diagnostic| diagnostic.path == path }
			assert_equal diagnostics.first.to_s, "#{path}:5: div keeps its call because its block is forwarded"

			Phlex::Compiler.compile(DiagnosticsCase::Component)

			assert Phlex::Compiler.explain(DiagnosticsCase::Component).map(&:message).include?("view_template is already compiled")
		ensure
			DiagnosticsCase.__send__(:remove_const, :Component)
			Object.__send__(:remove_const, :DiagnosticsCase)
		end
	end
end
