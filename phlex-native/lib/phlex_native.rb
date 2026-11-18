# frozen_string_literal: true

# A gem precompiled for several Ruby versions has a binary for each; otherwise there's just one.
begin
	require "phlex_native/#{RUBY_VERSION[/\A\d+\.\d+/]}/phlex_native"
rescue LoadError
	require "phlex_native/phlex_native"
end
