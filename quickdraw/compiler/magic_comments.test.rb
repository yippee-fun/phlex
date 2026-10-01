# frozen_string_literal: true

require "tmpdir"

class CompilerMagicCommentsTest < Quickdraw::Test
	def render_before_and_after_compiling(name, source)
		Dir.mktmpdir do |dir|
			path = File.join(dir, "#{name}.rb")
			File.write(path, source)
			load path

			component = Object.const_get(name)
			before = component.new.call
			Phlex::Compiler.compile(component)
			assert Phlex::Compiler::MAP.key?(component.instance_method(:view_template).source_location[0])

			[before, component.new.call]
		end
	end

	test "a frozen string literal comment anywhere in the leading comment block is forwarded" do
		results = render_before_and_after_compiling("MagicCommentsLeadingBlock", <<~RUBY)
			# typed: true
			# encoding: utf-8

			# frozen_string_literal: true
			class MagicCommentsLeadingBlock < Phlex::HTML
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>true", "<div>x</div>true"]
	end

	test "the dashed frozen string literal comment is forwarded" do
		results = render_before_and_after_compiling("MagicCommentsDashed", <<~RUBY)
			# Frozen-String-Literal: TRUE
			class MagicCommentsDashed < Phlex::HTML
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>true", "<div>x</div>true"]
	end

	test "a frozen string literal comment after the first token is ignored" do
		results = render_before_and_after_compiling("MagicCommentsAfterCode", <<~RUBY)
			class MagicCommentsAfterCode < Phlex::HTML
				# frozen_string_literal: true
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>false", "<div>x</div>false"]
	end

	test "the last leading frozen string literal comment wins" do
		results = render_before_and_after_compiling("MagicCommentsLastWins", <<~RUBY)
			# frozen_string_literal: true
			# frozen_string_literal: false
			class MagicCommentsLastWins < Phlex::HTML
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>false", "<div>x</div>false"]
	end

	test "a frozen string literal comment after a token the AST leaves out is ignored" do
		results = render_before_and_after_compiling("MagicCommentsAfterSemicolon", <<~RUBY)
			;
			# typed: true
			# frozen_string_literal: true
			class MagicCommentsAfterSemicolon < Phlex::HTML
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>false", "<div>x</div>false"]
	end

	test "an invalid frozen string literal value doesn't override an earlier valid one" do
		results = render_before_and_after_compiling("MagicCommentsInvalidValue", <<~RUBY)
			# frozen_string_literal: true
			# frozen_string_literal: yes
			class MagicCommentsInvalidValue < Phlex::HTML
				def view_template
					div { "x" }
					plain "abc".frozen?.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>true", "<div>x</div>true"]
	end

	test "the encoding comment is forwarded alongside frozen string literals" do
		results = render_before_and_after_compiling("MagicCommentsEncoding", <<~RUBY)
			# encoding: ascii-8bit
			# frozen_string_literal: true
			class MagicCommentsEncoding < Phlex::HTML
				def view_template
					div { "x" }
					plain "\#{__ENCODING__} \#{'abc'.encoding} \#{'abc'.frozen?}"
				end
			end
		RUBY

		assert_equal results, [
			"<div>x</div>ASCII-8BIT ASCII-8BIT true",
			"<div>x</div>ASCII-8BIT ASCII-8BIT true",
		]
	end

	test "an encoding comment Ruby ignores is not forwarded" do
		results = render_before_and_after_compiling("MagicCommentsIgnoredEncoding", <<~RUBY)
			# typed: true
			# encoding: ascii-8bit
			class MagicCommentsIgnoredEncoding < Phlex::HTML
				def view_template
					div { "x" }
					plain __ENCODING__.to_s
				end
			end
		RUBY

		assert_equal results, ["<div>x</div>UTF-8", "<div>x</div>UTF-8"]
	end
end
