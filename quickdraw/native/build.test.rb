# frozen_string_literal: true

require "fileutils"
require "tmpdir"

class NativeBuildTest < Quickdraw::Test
	EXT = File.expand_path("../../ext/phlex_native", __dir__)
	BUILDABLE = RUBY_ENGINE == "ruby" && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0")

	# Runs the extension's Rakefile as `gem install` does, returning whether it succeeded and what it installed.
	def self.install(env: {})
		Dir.mktmpdir do |dir|
			FileUtils.cp_r("#{EXT}/.", dir)
			out = File.join(dir, "out")
			IO.popen(env, [RbConfig.ruby, Gem.bin_path("rake", "rake"), "RUBYARCHDIR=#{out}"], chdir: dir, err: [:child, :out], &:read)

			yield $?.success?, Dir.glob("**/*.{so,bundle,dll}", base: out)
		end
	end

	def self.without_compilers
		dir = Dir.mktmpdir
		["gcc", "cc", "clang"].each do |name|
			path = File.join(dir, name)
			File.write(path, "#!/bin/sh\nexit 1\n")
			File.chmod(0o755, path)
		end
		{ "PATH" => "#{dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}" }
	end

	test "builds the extension only on CRuby 4.0 or later" do
		NativeBuildTest.install do |success, built|
			assert success
			assert_equal built, (BUILDABLE ? ["phlex_native/phlex_native.#{RbConfig::CONFIG['DLEXT']}"] : [])
		end
	end

	test "installs without the extension when there's no C compiler" do
		NativeBuildTest.install(env: NativeBuildTest.without_compilers) do |success, built|
			assert success
			assert_equal built, []
		end
	end

	test "installs without the extension when it doesn't compile" do
		NativeBuildTest.install(env: { "CONFIGURE_ARGS" => "--with-cflags=-include/phlex/does/not/exist.h" }) do |success, built|
			assert success
			assert_equal built, []
		end
	end

	test "installs without the extension when there's no make" do
		NativeBuildTest.install(env: { "MAKE" => "/phlex/does/not/exist/make" }) do |success, built|
			assert success
			assert_equal built, []
		end
	end

	test "installs without the extension when PHLEX_NATIVE is false" do
		NativeBuildTest.install(env: { "PHLEX_NATIVE" => "false" }) do |success, built|
			assert success
			assert_equal built, []
		end
	end

	test "falls back to Ruby when the extension can't be loaded" do
		Dir.mktmpdir do |dir|
			FileUtils.mkdir_p(File.join(dir, "phlex_native"))
			File.write(File.join(dir, "phlex_native", "phlex_native.#{RbConfig::CONFIG['DLEXT']}"), "not a shared library")

			script = <<~RUBY
				require "phlex"
				print defined?(Phlex::Native).inspect, " "
				print Class.new(Phlex::HTML) { def view_template = a(href: "/", class: ["a", :b]) }.call
			RUBY

			output = IO.popen([RbConfig.ruby, "-I", dir, "-e", script], err: [:child, :out], &:read)
			assert_equal $?.exitstatus, 0
			assert_equal output, %(nil <a href="/" class="a b"></a>)
		end
	end
end
