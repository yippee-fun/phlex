# frozen_string_literal: true

source "https://gem.coop"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

group :test do
	gem "sus"
	gem "quickdraw", github: "joeldrapper/quickdraw", ref: "bde2d5124320248627edc70141d2b4ca95d4e336"
	gem "simplecov", require: false
	gem "selenium-webdriver"
end

gem "nokogiri"

group :development do
	gem "rubocop"
	gem "ruby-lsp"
	gem "benchmark-ips"
end

gem "refract", "1.1.0"
