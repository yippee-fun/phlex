#!/usr/bin/env ruby
# frozen_string_literal: true

require "phlex"
require "benchmark/ips"

require_relative "fixtures/page"
require_relative "fixtures/layout"

RubyVM::YJIT.enable

sample = Example::Page.new.call
puts "#{sample.bytesize} bytes"

Benchmark.ips do |x|
	x.time = 5
	x.report("Page (before compile)") { Example::Page.new.call }
end

Phlex::Compiler.compile(Example::Page)
Phlex::Compiler.compile(Example::LayoutComponent)

sample = Example::Page.new.call
puts "#{sample.bytesize} bytes"

Benchmark.ips do |x|
	x.time = 5
	x.report("Page (after compile)") { Example::Page.new.call }
end
