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
	spec.required_ruby_version = ">= 3.3"

	spec.metadata["homepage_uri"] = spec.homepage
	spec.metadata["source_code_uri"] = "https://github.com/phlex-ruby/phlex"
	spec.metadata["changelog_uri"] = "https://github.com/phlex-ruby/phlex/releases"
	spec.metadata["funding_uri"] = "https://github.com/sponsors/joeldrapper"
	spec.metadata["rubygems_mfa_required"] = "true"
	spec.metadata["mailing_list_uri"] = "https://www.rubyforum.org/tag/phlex"

	spec.files = Dir[
		"README.md",
		"LICENSE.txt",
		"lib/**/*.rb",
		"ext/**/*.{c,rb}",
		"ext/**/Rakefile"
	]

	spec.require_paths = ["lib"]

	# Optional: skipped wherever it can’t be built, leaving Phlex in Ruby.
	# A Rakefile builds it, so installing doesn’t need make either.
	spec.extensions = ["ext/phlex_native/Rakefile"]

	spec.add_dependency "zeitwerk", "~>2.7"
	spec.add_dependency "refract", "~> 2.0.0"
	spec.add_dependency "rake", ">= 13.0" # builds the C extension
	spec.add_dependency "erb", ">= 5.0.2" # ERB::Escape is Ractor-safe from here
end
