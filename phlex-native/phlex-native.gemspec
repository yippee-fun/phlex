# frozen_string_literal: true

require_relative "../lib/phlex/version"

Gem::Specification.new do |spec|
	spec.name = "phlex-native"
	spec.version = Phlex::VERSION
	spec.authors = ["Joel Drapper"]
	spec.email = ["joel@drapper.me"]

	spec.summary = "A native extension that speeds up Phlex."
	spec.description = "Serialises Phlex attributes in C, falling back to Ruby for anything uncommon."
	spec.homepage = "https://www.phlex.fun"
	spec.license = "MIT"
	spec.required_ruby_version = ">= 3.2"

	spec.metadata["source_code_uri"] = "https://github.com/phlex-ruby/phlex"
	spec.metadata["rubygems_mfa_required"] = "true"

	spec.files = Dir["README.md", "lib/**/*.rb", "ext/**/*.{c,rb}"]
	spec.extensions = ["ext/phlex_native/extconf.rb"]
	spec.require_paths = ["lib"]

	spec.add_dependency "phlex", Phlex::VERSION
end
