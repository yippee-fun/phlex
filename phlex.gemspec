# frozen_string_literal: true

require_relative "lib/phlex/version"

Gem::Specification.new do |spec|
	spec.name = "phlex"
	spec.version = Phlex::VERSION
	spec.authors = ["Joel Drapper", "Will Cosgrove"]
	spec.email = ["joel@drapper.me"]

	spec.summary = "Object-oriented views in Ruby."
	spec.description = "Build HTML, SVG and CSV views with Ruby classes."
	spec.homepage = "https://www.phlex.fun"
	spec.license = "MIT"
	spec.required_ruby_version = ">= 3.2"

	spec.metadata["homepage_uri"] = spec.homepage
	spec.metadata["source_code_uri"] = "https://github.com/phlex-ruby/phlex"
	spec.metadata["changelog_uri"] = "https://github.com/phlex-ruby/phlex/releases"
	spec.metadata["funding_uri"] = "https://github.com/sponsors/joeldrapper"
	spec.metadata["rubygems_mfa_required"] = "true"

	spec.files = Dir[
		"README.md",
		"LICENSE.txt",
		"lib/**/*.rb"
	]

	spec.require_paths = ["lib"]

	spec.add_dependency "zeitwerk", "~>2.7"
	spec.add_dependency "refract", "~> 1.0"
end
