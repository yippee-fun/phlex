# frozen_string_literal: true

# Phlex works without this extension, so nothing here may fail `gem install`.
def skip(reason)
	warn "Phlex will serialise attributes in Ruby because its C extension #{reason}."
	File.write("Makefile", <<~MAKEFILE)
		all install static install-so install-rb clean distclean realclean:
		.PHONY: all install static install-so install-rb clean distclean realclean
	MAKEFILE
	exit
end

skip("supports only CRuby") unless RUBY_ENGINE == "ruby"
skip("needs Ruby 4.0 or later") unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0")
skip("was turned off with PHLEX_NATIVE=false") if ENV["PHLEX_NATIVE"] == "false"

begin
	require "mkmf"

	append_cflags(["-O3", "-Wall", "-Wextra", "-Wno-unused-parameter"])

	if ENV["PHLEX_NATIVE_SANITIZE"] == "true"
		sanitizers = "-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
		$CFLAGS << " #{sanitizers} -O1"
		$LDFLAGS << " #{sanitizers}"
	end

	compiles = try_compile(File.read(File.join(__dir__, "phlex_native.c")))
rescue StandardError, SystemExit => e
	skip("couldn’t be configured (#{e.message.lines.first&.strip})")
end

skip("didn’t compile (see mkmf.log)") unless compiles

create_makefile("phlex_native/phlex_native")
