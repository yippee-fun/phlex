#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"
require "selenium-webdriver"

ASCII_CHARS = (0..127).to_set(&:chr)

class Layout < Phlex::HTML
	def view_template(&block)
		doctype
		html do
			head do
				meta(charset: "utf-8")
			end

			body(&block)
		end
	end
end

class JavaScriptLinks < Phlex::HTML
	def initialize(char)
		@char = char
	end

	def view_template
		render Layout do
			# Standard JavaScript link
			a(href: "javascript:alert(1)") { "x" }

			# With capitalization
			a(href: "Javascript:alert(1)") { "x" }

			# With extra "javascript:" prefixes
			a(href: "javascript:javascript:alert(1)") { "x" }
			a(href: "javascript:javascript:javascript:alert(1)") { "x" }

			# With extra "javascript:" prefixes and capitalization
			a(href: "javascript:Javascript:alert(1)") { "x" }
			a(href: "Javascript:javascript:alert(1)") { "x" }

			a(href: "#{@char}javascript:alert(1)") { "x" }
			a(href: "j#{@char}avascript:alert(1)") { "x" }
			a(href: "ja#{@char}vascript:alert(1)") { "x" }
			a(href: "jav#{@char}ascript:alert(1)") { "x" }
			a(href: "java#{@char}script:alert(1)") { "x" }
			a(href: "javas#{@char}cript:alert(1)") { "x" }
			a(href: "javasc#{@char}ript:alert(1)") { "x" }
			a(href: "javascr#{@char}ipt:alert(1)") { "x" }
			a(href: "javascr#{@char}ipt:alert(1)") { "x" }
			a(href: "javascri#{@char}pt:alert(1)") { "x" }
			a(href: "javascrip#{@char}t:alert(1)") { "x" }
			a(href: "javascript#{@char}:alert(1)") { "x" }
			a(href: "javascript:#{@char}alert(1)") { "x" }

			a(href: "#{@char}#{@char}javascript:alert(1)") { "x" }
			a(href: "j#{@char}#{@char}avascript:alert(1)") { "x" }
			a(href: "ja#{@char}#{@char}vascript:alert(1)") { "x" }
			a(href: "jav#{@char}#{@char}ascript:alert(1)") { "x" }
			a(href: "java#{@char}#{@char}script:alert(1)") { "x" }
			a(href: "javas#{@char}#{@char}cript:alert(1)") { "x" }
			a(href: "javasc#{@char}#{@char}ript:alert(1)") { "x" }
			a(href: "javascr#{@char}#{@char}ipt:alert(1)") { "x" }
			a(href: "javascr#{@char}#{@char}ipt:alert(1)") { "x" }
			a(href: "javascri#{@char}#{@char}pt:alert(1)") { "x" }
			a(href: "javascrip#{@char}#{@char}t:alert(1)") { "x" }
			a(href: "javascript#{@char}#{@char}:alert(1)") { "x" }
			a(href: "javascript:#{@char}#{@char}alert(1)") { "x" }

			a(href: "#{@char}Javascript:alert(1)") { "x" }
			a(href: "J#{@char}avascript:alert(1)") { "x" }
			a(href: "Ja#{@char}vascript:alert(1)") { "x" }
			a(href: "Jav#{@char}ascript:alert(1)") { "x" }
			a(href: "Java#{@char}script:alert(1)") { "x" }
			a(href: "Javas#{@char}cript:alert(1)") { "x" }
			a(href: "Javasc#{@char}ript:alert(1)") { "x" }
			a(href: "Javascr#{@char}ipt:alert(1)") { "x" }
			a(href: "Javascr#{@char}ipt:alert(1)") { "x" }
			a(href: "Javascri#{@char}pt:alert(1)") { "x" }
			a(href: "Javascrip#{@char}t:alert(1)") { "x" }
			a(href: "Javascript#{@char}:alert(1)") { "x" }
			a(href: "Javascript:#{@char}alert(1)") { "x" }

			a(href: "#{@char}#{@char}Javascript:alert(1)") { "x" }
			a(href: "J#{@char}#{@char}avascript:alert(1)") { "x" }
			a(href: "Ja#{@char}#{@char}vascript:alert(1)") { "x" }
			a(href: "Jav#{@char}#{@char}ascript:alert(1)") { "x" }
			a(href: "Java#{@char}#{@char}script:alert(1)") { "x" }
			a(href: "Javas#{@char}#{@char}cript:alert(1)") { "x" }
			a(href: "Javasc#{@char}#{@char}ript:alert(1)") { "x" }
			a(href: "Javascr#{@char}#{@char}ipt:alert(1)") { "x" }
			a(href: "Javascr#{@char}#{@char}ipt:alert(1)") { "x" }
			a(href: "Javascri#{@char}#{@char}pt:alert(1)") { "x" }
			a(href: "Javascrip#{@char}#{@char}t:alert(1)") { "x" }
			a(href: "Javascript#{@char}#{@char}:alert(1)") { "x" }
			a(href: "Javascript:#{@char}#{@char}alert(1)") { "x" }
		end
	end
end

class XSSWithStrings < Phlex::HTML
	def view_template
		render Layout do
			File.open("fixtures/xss.txt") do |file|
				file.each_line do |line|
					div(class: line) { line }
					svg do |s|
						s.cdata(line)
						s.cdata { line }
					end
				end
			end
		end
	end
end

class XSSWithSymbols < Phlex::HTML
	def view_template
		render Layout do
			File.open("fixtures/xss.txt") do |file|
				file.each_line do |line|
					div(class: line.to_sym) { line.to_sym }
				end
			end
		end
	end
end

class OnClick < Phlex::HTML
	def initialize(char)
		@char = char
	end

	def view_template
		render Layout do
			ignore_warnings { div("#{@char}onclick" => "alert(1)") { "x" } }
			ignore_warnings { div("o#{@char}nclick" => "alert(1)") { "x" } }
			ignore_warnings { div("on#{@char}click" => "alert(1)") { "x" } }
			ignore_warnings { div("onc#{@char}lick" => "alert(1)") { "x" } }
			ignore_warnings { div("oncl#{@char}ick" => "alert(1)") { "x" } }
			ignore_warnings { div("oncli#{@char}ck" => "alert(1)") { "x" } }
			ignore_warnings { div("onclic#{@char}k" => "alert(1)") { "x" } }
			ignore_warnings { div("onclick#{@char}" => "alert(1)") { "x" } }

			ignore_warnings { div("#{@char}#{@char}onclick" => "alert(1)") { "x" } }
			ignore_warnings { div("o#{@char}#{@char}nclick" => "alert(1)") { "x" } }
			ignore_warnings { div("on#{@char}#{@char}click" => "alert(1)") { "x" } }
			ignore_warnings { div("onc#{@char}#{@char}lick" => "alert(1)") { "x" } }
			ignore_warnings { div("oncl#{@char}#{@char}ick" => "alert(1)") { "x" } }
			ignore_warnings { div("oncli#{@char}#{@char}ck" => "alert(1)") { "x" } }
			ignore_warnings { div("onclic#{@char}#{@char}k" => "alert(1)") { "x" } }
			ignore_warnings { div("onclick#{@char}#{@char}" => "alert(1)") { "x" } }

			ignore_warnings { div("#{@char}onclick": "alert(1)") { "x" } }
			ignore_warnings { div("o#{@char}nclick": "alert(1)") { "x" } }
			ignore_warnings { div("on#{@char}click": "alert(1)") { "x" } }
			ignore_warnings { div("onc#{@char}lick": "alert(1)") { "x" } }
			ignore_warnings { div("oncl#{@char}ick": "alert(1)") { "x" } }
			ignore_warnings { div("oncli#{@char}ck": "alert(1)") { "x" } }
			ignore_warnings { div("onclic#{@char}k": "alert(1)") { "x" } }
			ignore_warnings { div("onclick#{@char}": "alert(1)") { "x" } }

			ignore_warnings { div("#{@char}#{@char}onclick": "alert(1)") { "x" } }
			ignore_warnings { div("o#{@char}#{@char}nclick": "alert(1)") { "x" } }
			ignore_warnings { div("on#{@char}#{@char}click": "alert(1)") { "x" } }
			ignore_warnings { div("onc#{@char}#{@char}lick": "alert(1)") { "x" } }
			ignore_warnings { div("oncl#{@char}#{@char}ick": "alert(1)") { "x" } }
			ignore_warnings { div("oncli#{@char}#{@char}ck": "alert(1)") { "x" } }
			ignore_warnings { div("onclic#{@char}#{@char}k": "alert(1)") { "x" } }
			ignore_warnings { div("onclick#{@char}#{@char}": "alert(1)") { "x" } }
		end
	end

	def ignore_warnings
		yield
	rescue ArgumentError
		# ignore
	end
end

class Browser
	MUTEX = { safari: Mutex.new, chrome: Mutex.new, firefox: Mutex.new }

	def self.open(driver)
		MUTEX.fetch(driver).synchronize do
			browser = new(Selenium::WebDriver.for(driver))
			yield(browser)
			browser.quit
		end
	end

	def self.open_each
		[:safari, :chrome, :firefox].map do |driver|
			Thread.new do
				self.open(driver) do |browser|
					yield(browser)
				end
			end
		end.each(&:join)
	end

	def initialize(driver)
		@driver = driver
	end

	attr_reader :driver

	def load_string(string)
		navigate_to("data:text/html,#{ERB::Util.url_encode(string)}")
	end

	def navigate_to(url)
		@driver.navigate.to(url)
	end

	def execute_script(script)
		@driver.execute_script(script)
	end

	def each_alert
		while (next_alert = alert)
			yield(next_alert)
		end
	end

	def alert
		@driver.switch_to.alert
	rescue Selenium::WebDriver::Error::NoSuchAlertError
		nil
	end

	def quit
		@driver.quit
	end
end

Browser.open_each do |browser|
	ASCII_CHARS.each do |char|
		browser.load_string(JavaScriptLinks.new(char).call)
		browser.execute_script("document.querySelectorAll('a').forEach(function(a) { a.click(); });")
		browser.each_alert do |alert|
			unless alert.text == "Safari cannot open the page because the address is invalid."
				raise "Failed with #{char.codepoints}"
			end

			alert.accept
		end

		browser.load_string(OnClick.new(char).call)
		browser.execute_script("document.querySelectorAll('div').forEach(function(div) { div.click(); });")
		browser.each_alert do
			raise "Failed with #{char.codepoints}"
		end
	end

	browser.load_string(XSSWithStrings.new.call)
	browser.execute_script("document.querySelectorAll('div').forEach(function(div) { div.click(); });")

	if browser.alert
		raise "Failed with strings"
	end

	browser.load_string(XSSWithSymbols.new.call)
	browser.execute_script("document.querySelectorAll('div').forEach(function(div) { div.click(); });")

	if browser.alert
		raise "Failed with symbols"
	end
end
