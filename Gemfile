# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

group :test do
	gem "sus"
	gem "quickdraw", git: "https://github.com/joeldrapper/quickdraw.git", ref: "06615ef2554dabec4fbf6cf2848fb9493842fd05"
	gem "simplecov", require: false
	gem "selenium-webdriver"
end

gem "nokogiri"

group :development do
	gem "rubocop"
	gem "ruby-lsp"
	gem "benchmark-ips"
end
