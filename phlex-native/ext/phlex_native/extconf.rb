# frozen_string_literal: true

require "mkmf"

append_cflags(["-O3", "-Wall", "-Wextra", "-Wno-unused-parameter"])

if ENV["PHLEX_NATIVE_SANITIZE"] == "true"
	sanitizers = "-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
	$CFLAGS << " #{sanitizers} -O1"
	$LDFLAGS << " #{sanitizers}"
end

create_makefile("phlex_native/phlex_native")
