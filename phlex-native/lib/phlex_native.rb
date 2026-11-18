# frozen_string_literal: true

# Precompiled gems have a binary for each Ruby version; gems built from source have one.
begin
	require "phlex_native/#{RUBY_VERSION[/\A\d+\.\d+/]}/phlex_native"
rescue LoadError
	require "phlex_native/phlex_native"
end
