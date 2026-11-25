# frozen_string_literal: true

require "nokogiri"

Bundler.require :test

require "phlex"

if ENV["PHLEX_NATIVE"] == "true" && !defined?(Phlex::Native)
	raise "PHLEX_NATIVE is set but the extension didn't load. Run `bundle exec rake compile`."
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
