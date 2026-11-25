# frozen_string_literal: true

require_relative "../lib/phlex/version"

# Counts the releases made since Phlex's last one: 1 makes this 3.0.0.1.
revision = nil

Gem::Specification.new do |spec|
	spec.name = "phlex-native"
	spec.version = [Phlex::VERSION, revision].compact.join(".")
	spec.authors = ["Joel Drapper"]
	spec.email = ["joel@drapper.me"]

	spec.summary = "A native extension that speeds up Phlex."
	spec.description = "Serialises Phlex attributes in C, falling back to Ruby for anything uncommon."
	spec.homepage = "https://www.phlex.fun"
	spec.license = "MIT"
	spec.required_ruby_version = ">= 4.0"

	spec.metadata["source_code_uri"] = "https://github.com/phlex-ruby/phlex"
	spec.metadata["rubygems_mfa_required"] = "true"

	spec.files = Dir["README.md", "lib/**/*.rb", "ext/**/*.{c,rb}"]
	spec.extensions = ["ext/phlex_native/extconf.rb"]
	spec.require_paths = ["lib"]

	# The C mirrors this version's Ruby exactly, so it can't be used with any other.
	spec.add_dependency "phlex", Phlex::VERSION
end
