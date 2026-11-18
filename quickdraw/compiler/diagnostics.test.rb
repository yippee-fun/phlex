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
				"3: no live method is defined at this line, so the file has changed since it was loaded",
			]

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(EditedCase) }
			assert_equal error.message, "#{path}:3: no live method is defined at this line, so the file has changed since it was loaded"
			refute Phlex::Compiler::MAP.key?(EditedCase.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :EditedCase)
		end
	end

	test "a compiled method is reported as such" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "clean.rb")
			File.write(path, <<~RUBY)
				class CleanCase < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			load path

			Phlex::Compiler.compile(CleanCase)

			assert_equal Phlex::Compiler.explain(CleanCase).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"2: view_template is already compiled",
			]
		ensure
			Object.__send__(:remove_const, :CleanCase)
		end
	end

	test "a definition naming a moved method in another class doesn't hide the edit" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "moved.rb")
			File.write(path, <<~RUBY)
				class MovedCase < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			load path

			File.write(path, <<~RUBY)
				# The call below is at the line view_template was loaded from.
				class MovedRegistry; attr_reader :view_template; end
				class MovedCase < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(MovedCase) }
			assert_equal error.message, "#{path}:4: no live method is defined at this line, so the file has changed since it was loaded"
		ensure
			Object.__send__(:remove_const, :MovedCase)
		end
	end

	test "a definition that a later `def` replaces doesn't hide the edit" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "replaced.rb")
			File.write(path, <<~RUBY)
				class ReplacedCase < Phlex::HTML
					def view_template = div { "x" }
				end
			RUBY
			load path

			File.write(path, <<~RUBY)
				class ReplacedCase < Phlex::HTML
					attr_reader :view_template
					def view_template = div { "x" }
				end
			RUBY

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(ReplacedCase) }
			assert_equal error.message, "#{path}:3: no live method is defined at this line, so the file has changed since it was loaded"
		ensure
			Object.__send__(:remove_const, :ReplacedCase)
		end
	end

	test "a descendant overriding instance_method doesn't stop its ancestor compiling" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "reflective.rb")
			File.write(path, <<~RUBY)
				class ReflectiveCase < Phlex::HTML
					def view_template = div { "x" }
					alias_method :other, :view_template
				end

				class ReflectiveLegacy
					ruby2_keywords def unrelated(*args) = args
				end
			RUBY
			load path

			descendant = Class.new(ReflectiveCase) do
				def self.instance_method(*) = raise("overridden")
				def self.instance_methods(*) = raise("overridden")
				def self.private_instance_methods(*) = raise("overridden")
				def self.subclasses = raise("overridden")
				def own = nil
			end

			Phlex::Compiler.compile(ReflectiveCase)
			assert Phlex::Compiler::MAP.key?(ReflectiveCase.instance_method(:view_template).source_location[0])
		ensure
			# The class outlives the test, so it mustn't break other compiles.
			%i[instance_method instance_methods private_instance_methods subclasses].each do |name|
				descendant&.singleton_class&.__send__(:remove_method, name)
			end

			Object.__send__(:remove_const, :ReflectiveCase)
			Object.__send__(:remove_const, :ReflectiveLegacy)
		end
	end

	test "a call that doesn't define methods doesn't hide the edit" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "registered.rb")
			File.write(path, <<~RUBY)
				class RegisteredCase < Phlex::HTML
					def view_template = div { "x" }
					def self.register(*) = nil
				end
			RUBY
			load path

			File.write(path, <<~RUBY)
				class RegisteredCase < Phlex::HTML
					register(:view_template)
					def view_template = div { "x" }
					def self.register(*) = nil
				end
			RUBY

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(RegisteredCase) }
			assert_equal error.message, "#{path}:3: no live method is defined at this line, so the file has changed since it was loaded"
		ensure
			Object.__send__(:remove_const, :RegisteredCase)
		end
	end

	test "explain reports a `using` it can't reproduce rather than raising" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "dynamic_using.rb")
			File.write(path, <<~RUBY)
				module DynamicUsingRefinement
					refine(String) { def shout = upcase }
				end

				refinement = DynamicUsingRefinement
				using refinement

				class DynamicUsingCase < Phlex::HTML
					def view_template = div { "x".shout }
				end
			RUBY
			load path

			assert_equal Phlex::Compiler.explain(DynamicUsingCase).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"6: this `using` isn't a plain top-level statement naming a constant, which the compiler can't reproduce",
			]
		ensure
			Object.__send__(:remove_const, :DynamicUsingCase)
			Object.__send__(:remove_const, :DynamicUsingRefinement)
		end
	end

	test "a method-defining call at a compiled method's old line doesn't hide the edit" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "generated.rb")
			File.write(path, <<~RUBY)
				class GeneratedCase < Phlex::HTML
					def view_template = div { "x" }
					def self.attr_reader(*) = nil
				end
			RUBY
			load path
			Phlex::Compiler.compile(GeneratedCase)

			File.write(path, <<~RUBY)
				class GeneratedCase < Phlex::HTML
					attr_reader :view_template
					define_method(:view_template) { div { "x" } }
					def self.attr_reader(*) = nil
				end
			RUBY

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.recompile(GeneratedCase) }
			assert_equal error.message, "#{path}:2: view_template was compiled from this line, which no longer defines it, so the file has changed since it was loaded"
		ensure
			Object.__send__(:remove_const, :GeneratedCase)
		end
	end

	# Only CRuby can tell a method made by `def` from one made otherwise.
	test "definitions that aren't live, or aren't compiled, aren't refused" do
		next unless defined?(RubyVM::InstructionSequence)

		Dir.mktmpdir do |dir|
			path = File.join(dir, "superseded.rb")
			File.write(path, <<~RUBY)
				class SupersededUnrelated; def x = 1; def y = 2; end

				class SupersededCase < Phlex::HTML
					def self.register(*) = nil
					register("\\xFF")
					def initialize = @title = "live"
					def view_template = h1 { title }
					def title = "default"
					attr_reader :title
					def subtitle = "default"
					define_method(:subtitle) { "live" }
				end
			RUBY
			load path

			assert_equal Phlex::Compiler.explain(SupersededCase).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, []

			Phlex::Compiler.compile(SupersededCase)
			assert_equal SupersededCase.new.call, "<h1>live</h1>"
			assert Phlex::Compiler::MAP.key?(SupersededCase.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :SupersededCase)
			Object.__send__(:remove_const, :SupersededUnrelated)
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
				"12: plain keeps its call because its argument isn't a literal or an interpolation",
				"13: raw keeps its call because its argument isn't safe with a string literal",
				"14: whitespace keeps its call because it has arguments",
				"15: comment keeps its call because its block is forwarded or it has parameters or contains a return, break, next or local assignment",
				"16: doctype keeps its call because it has arguments or a block",
				"17: fragment keeps its call because its block has parameters or is forwarded",
				"25: more than one method is defined on this line, so the compiler can't tell which definition is live",
				"27: __phlex_x__ is a local the compiler reserves; names starting with __phlex_ can't be used",
				"32: hr keeps its call because it's in a parameter default",
			]

			assert diagnostics.all? { |diagnostic| diagnostic.path == path }
			assert_equal diagnostics.first.to_s, "#{path}:5: div keeps its call because its block is forwarded"

			# Compiling refuses the first construct it can't compile faithfully.
			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(DiagnosticsCase::Component) }
			assert_equal error.message, "#{path}:25: more than one method is defined on this line, so the compiler can't tell which definition is live"
		ensure
			DiagnosticsCase.__send__(:remove_const, :Component)
			Object.__send__(:remove_const, :DiagnosticsCase)
		end
	end
end
