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

# Components compile on first render, and one that would fall back to rendering
# uncompiled raises instead. PHLEX_COMPILER=false runs the suite uncompiled.
if ENV["PHLEX_COMPILER"] == "false"
	Phlex::Compiler.disable!
else
	Phlex::Compiler.enable!(on_failure: -> (component, error) { raise error })
end

# Quickdraw loads each test file into an anonymous module, but the compiler
# compiles a component by reopening its class from the top level, as it would
# be in an app. Loading test files at the top level lets components defined in
# them compile.
module QuickdrawTopLevelLoad
	TEST_ROOT = File.expand_path("../quickdraw", __dir__)

	def load(path, wrap = false)
		wrap = false if Module === wrap && File.expand_path(path).start_with?("#{TEST_ROOT}/")
		super
	end
end

Kernel.singleton_class.prepend(QuickdrawTopLevelLoad)
