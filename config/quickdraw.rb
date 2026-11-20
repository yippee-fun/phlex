# frozen_string_literal: true

require "nokogiri"

if ENV["COVERAGE"] == "true"
	require "simplecov"

	SimpleCov.start do
		command_name "quickdraw"
		enable_coverage_for_eval
		enable_for_subprocesses true
		enable_coverage :branch
		add_filter %r{^/fixtures/}

		add_group "SGML", "lib/phlex/sgml"
		add_group "HTML", "lib/phlex/html"
		add_group "SVG", "lib/phlex/svg"
		add_group "CSV", "lib/phlex/csv"
	end
end

Bundler.require :test

if ENV["PHLEX_NATIVE"] == "true"
	$LOAD_PATH.unshift(File.expand_path("../phlex-native/lib", __dir__))
end

require "phlex"

if ENV["PHLEX_NATIVE"] == "true" && !defined?(Phlex::Native)
	raise "PHLEX_NATIVE is set but the extension didn't load. Run `rake compile` in phlex-native."
end

Phlex::Loader.eager_load

# Previous content of test helper now starts here
$LOAD_PATH.unshift(File.expand_path("../fixtures", __dir__))

Quickdraw.configure do |config|
	# Quickdraw runs several browsers in forked groups, which TruffleRuby can't.
	if Process.respond_to?(:fork)
		config.browser("quickdraw/browser/**/*.test.rb", browsers: [:chromium, :webkit])
	else
		config.browser("quickdraw/browser/**/*.test.rb", browser: :chromium)
	end

	# Under AddressSanitizer, phlex-native's differential tests take minutes.
	config.timeout = 1800 if ENV["PHLEX_NATIVE_SANITIZE"] == "true"
end
