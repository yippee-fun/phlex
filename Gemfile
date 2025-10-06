# frozen_string_literal: true

source "https://gem.coop"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

group :test do
	gem "sus"
	gem "quickdraw", github: "joeldrapper/quickdraw"
	gem "simplecov", require: false
	gem "selenium-webdriver"
end

gem "nokogiri"

group :development do
	gem "rubocop"
	gem "ruby-lsp"
	gem "benchmark-ips"
end

gem "refract", github: "yippee-fun/refract"
