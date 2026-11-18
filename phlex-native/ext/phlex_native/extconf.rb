# frozen_string_literal: true

require "mkmf"

append_cflags(["-O3", "-Wall", "-Wextra", "-Wno-unused-parameter"])
create_makefile("phlex_native/phlex_native")
