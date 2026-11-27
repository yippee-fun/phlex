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
					ul { |list| li; list }
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

				def shadowed
					tap { plain title; title = "local" }
				end

				def reserved_call
					div { __phlex_state__ }
				end

				def running_total
					total = 0
					tap { [1].each { |n| total += n }; total += 1; div { total.to_s } }
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
			refute Phlex.__compiled_source_maps__.key?(EditedCase.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :EditedCase)
		end
	end

	# Only CRuby can tell an attr_reader from a def, so elsewhere one counts as a def with no definition at its line.
	test "a method that's live in another class of the file doesn't count as edited" do
		stub(Phlex::Compiler, :defined_by_def?) { |_method| true }

		Dir.mktmpdir do |dir|
			path = File.join(dir, "elsewhere.rb")
			File.write(path, <<~RUBY)
				class ElsewhereDefined < Phlex::HTML
					def store = "defined"
					def view_template = div { store }
				end

				class ElsewhereRead < Phlex::HTML
					attr_reader :store
					def view_template = span { "read" }
				end
			RUBY
			load path

			refute_raises { Phlex::Compiler.compile(ElsewhereRead) }
			refute_raises { Phlex::Compiler.compile(ElsewhereDefined) }

			assert Phlex.__compiled_source_maps__.key?(ElsewhereDefined.instance_method(:view_template).source_location[0])
			assert_equal ElsewhereDefined.new.call, "<div>defined</div>"
		ensure
			Object.__send__(:remove_const, :ElsewhereDefined)
			Object.__send__(:remove_const, :ElsewhereRead)
		end
	end

	test "a def replaced by a method that looks like a def in the same class still counts as edited" do
		stub(Phlex::Compiler, :defined_by_def?) { |_method| true }

		Dir.mktmpdir do |dir|
			path = File.join(dir, "replaced.rb")
			File.write(path, <<~RUBY)
				class ReplacedDefinition < Phlex::HTML
					def store = "defined"
					attr_reader :store
					def view_template = div { "x" }
				end
			RUBY
			load path

			error = assert_raises(Phlex::Compiler::Error) { Phlex::Compiler.compile(ReplacedDefinition) }
			assert_equal error.message, "#{path}:2: no live method is defined at this line, so the file has changed since it was loaded"
		ensure
			Object.__send__(:remove_const, :ReplacedDefinition)
		end
	end

	test "a compiled method is explained from its source, as it was before compiling" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "clean.rb")
			File.write(path, <<~RUBY)
				class CleanCase < Phlex::HTML
					def view_template = div(**{}) { "x" }
				end
			RUBY
			load path

			before = Phlex::Compiler.explain(CleanCase)
			Phlex::Compiler.compile(CleanCase)

			assert_equal Phlex::Compiler.explain(CleanCase), before
			assert_equal before.map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"2: div's attributes are serialised together because a key is splatted or isn't a literal",
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
			assert Phlex.__compiled_source_maps__.key?(ReflectiveCase.instance_method(:view_template).source_location[0])
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
		skip "Needs RubyVM::InstructionSequence" unless defined?(RubyVM::InstructionSequence)

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
			assert Phlex.__compiled_source_maps__.key?(SupersededCase.instance_method(:view_template).source_location[0])
		ensure
			Object.__send__(:remove_const, :SupersededCase)
			Object.__send__(:remove_const, :SupersededUnrelated)
		end
	end

	test "past the block depth limit, only its element and helper calls are reported" do
		Dir.mktmpdir do |dir|
			path = File.join(dir, "deep.rb")
			File.write(path, <<~RUBY)
				class DeepCase < Phlex::HTML
					def initialize(periods) = @periods = periods

					def view_template
						render DeepCaseActivity.new do |activity|
							@periods.each do |period|
								activity.period(period[:title]) do |entries|
									period[:events].each do |event|
										entries.event { event }
									end
								end
							end
						end
					end
				end

				class DeepCaseDeeper < Phlex::HTML
					def view_template
						[1].each { [2].each { [3].each { [4].each { |n|
							div { [5].each { |m, x = (hr; nil)| span { m }; render(DeepCaseActivity.new) { nil }; plain "text"; entries(m) } }
						} } } }
					end

					def entries(m) = m
				end

				class DeepCaseSuper < Phlex::HTML
					def view_template = b
					def b(...) = [1].each { [2].each { [3].each { [4].each { [5].each { super; fragment(:f) { i } } } } } }
				end

				class DeepCaseActivity < Phlex::HTML
					def view_template = ul { yield self }
					def period(title) = li { h2 { title }; yield self }
					def event = li { yield }
				end
			RUBY
			load path

			assert_equal Phlex::Compiler.explain(DeepCase), []
			assert_equal Phlex::Compiler.explain(DeepCaseDeeper).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"20: hr keeps its call because it's in a parameter default",
				"20: span keeps its call because it's more than 4 blocks deep",
				"20: plain keeps its call because it's more than 4 blocks deep",
			]
			assert_equal Phlex::Compiler.explain(DeepCaseSuper).map { |diagnostic| "#{diagnostic.line}: #{diagnostic.message}" }, [
				"29: super keeps its call because it's more than 4 blocks deep",
				"29: i keeps its call because it's more than 4 blocks deep",
			]

			periods = [{ title: "Today", events: ["a", "b"] }, { title: "Later", events: ["c"] }]
			expected = [DeepCase.new(periods).call, DeepCaseDeeper.new.call, DeepCaseSuper.new.call]

			Phlex::Compiler.compile(DeepCase)
			Phlex::Compiler.compile(DeepCaseDeeper)
			Phlex::Compiler.compile(DeepCaseSuper)

			assert_equal [DeepCase.new(periods).call, DeepCaseDeeper.new.call, DeepCaseSuper.new.call], expected
			assert_equal expected[2], "<b></b><i></i>"
			assert_equal expected[1], "<div><hr><span>5</span><ul></ul>text</div>"
			assert_equal expected[0], "<ul><li><h2>Today</h2><li>a</li><li>b</li></li><li><h2>Later</h2><li>c</li></li></ul>"
		ensure
			Object.__send__(:remove_const, :DeepCase)
			Object.__send__(:remove_const, :DeepCaseDeeper)
			Object.__send__(:remove_const, :DeepCaseSuper)
			Object.__send__(:remove_const, :DeepCaseActivity)
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
				"27: __phlex_x__ is a name the compiler reserves for locals; names starting with __phlex_ can't be used",
				"32: hr keeps its call because it's in a parameter default",
				"37: calls in this block are left to the runtime because `title` is called before it's assigned",
				"40: __phlex_state__ is a name the compiler reserves for locals; names starting with __phlex_ can't be used",
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

	# bson includes a module defining == into NilClass. Compiled code and the
	# runtime both reach it only through ===, so they still agree.
	test "a == defined in Ruby on nil and true doesn't stop compiling" do
		output = in_ruby(<<~RUBY)
			module Specialized
				def ==(other) = self.class == other.class
			end

			NilClass.include(Specialized)
			TrueClass.include(Specialized)
		RUBY

		compiled, before, after = output.lines(chomp: true)
		assert_equal compiled, "true"
		assert_equal after, before
	end

	# Only CRuby can tell a core method was replaced before the compiler loaded,
	# so this replaces it after.
	test "a === redefined on nil stops compiling" do
		output = in_ruby(<<~RUBY)
			Phlex::Compiler::CoreCalls
			NilClass.prepend(Module.new { def ===(other) = super })
		RUBY

		assert output.include?("NilClass#=== is redefined, and compiled code calls it where the runtime calls the original")
	end

	private def in_ruby(setup)
		Dir.mktmpdir do |dir|
			component_path = File.join(dir, "component.rb")
			script_path = File.join(dir, "script.rb")

			File.write(component_path, <<~RUBY)
				# frozen_string_literal: true
				class RedefinedCore < Phlex::HTML
					def initialize(truthy, impostor)
						@truthy = truthy
						@impostor = impostor
					end

					def view_template
						div(hidden: @truthy)
						div { @impostor }
					end
				end
			RUBY

			File.write(script_path, <<~RUBY)
				require "phlex"
				require "phlex/compiler"
				#{setup}
				load #{component_path.inspect}

				impostor = Object.new
				def impostor.class = NilClass
				truthy = Object.new
				def truthy.class = TrueClass

				render = -> { RedefinedCore.new(truthy, impostor).call rescue $!.class.name }
				before = render.()
				Phlex::Compiler.compile(RedefinedCore)
				puts Phlex::Compiler.compiled?(RedefinedCore), before, render.()
			RUBY

			IO.popen([RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), script_path], err: [:child, :out], &:read)
		end
	end
end
