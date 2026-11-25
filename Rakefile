# frozen_string_literal: true

require "rake/extensiontask"

Rake::ExtensionTask.new("phlex_native", Gem::Specification.load(File.expand_path("phlex.gemspec", __dir__))) do |ext|
	ext.lib_dir = "lib/phlex_native"
end
