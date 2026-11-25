#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders each scenario with one Phlex `lib` directory and reports i/s, output throughput and allocations.
#
#   PHLEX_LIB=path/to/lib ruby --yjit bench.rb [--no-compile] [--json PATH] [--time SECONDS] [--only REGEXP] [--digest]
#
# The "page" scenario is the repo's normal benchmark (benchmarks/compiler.rb), loaded from this checkout's fixtures
# unless FIXTURES names another directory.

require "optparse"
require "json"
require "digest"

options = { compile: true, time: 3.0, warmup: 2.0 }

OptionParser.new do |parser|
	parser.on("--no-compile") { options[:compile] = false }
	parser.on("--json PATH") { |value| options[:json] = value }
	parser.on("--time SECONDS", Float) { |value| options[:time] = value }
	parser.on("--warmup SECONDS", Float) { |value| options[:warmup] = value }
	parser.on("--only REGEXP") { |value| options[:only] = Regexp.new(value) }
	parser.on("--digest") { options[:digest] = true }
end.parse!

$LOAD_PATH.unshift(File.expand_path(ENV.fetch("PHLEX_LIB")))

require "phlex"
require "benchmark/ips"

# Bundler may have loaded another checkout's version.rb through its gemspec, so read this one's.
version = File.read(File.join(ENV.fetch("PHLEX_LIB"), "phlex/version.rb"))[/VERSION = "([^"]+)"/, 1]
three = Phlex::Compiler.respond_to?(:disable!)

Phlex::Compiler.disable! if three && !options[:compile]
abort "Phlex #{version} doesn't compile on first render" if !three && options[:compile]

native = defined?(Phlex::Native) ? true : false

fixtures = File.expand_path(ENV.fetch("FIXTURES", File.join(__dir__, "../../fixtures")))
require File.join(fixtures, "page")
require File.join(fixtures, "layout")
require_relative "scenarios"

SCENARIOS = {
	"page" => -> { Example::Page.new.call },
	"dashboard" => -> { Bench::Dashboard.new.call },
	"article" => -> { Bench::Article.new.call },
	"catalogue" => -> { Bench::Catalogue.new.call },
	"settings_form" => -> { Bench::SettingsForm.new.call },
}.freeze

scenarios = options[:only] ? SCENARIOS.select { |name, _| options[:only].match?(name) } : SCENARIOS

bytes = scenarios.to_h { |name, scenario| [name, scenario.call.bytesize] }

if three
	classes = [Example::Page, Example::LayoutComponent, Bench::Dashboard, Bench::Article, Bench::Catalogue, Bench::SettingsForm, *Bench::UI.constants.map { |c| Bench::UI.const_get(c) }]
	compiled = classes.select { |klass| Phlex::Compiler.compiled?(klass) }
	if options[:compile]
		uncompiled = classes - compiled
		abort "Not compiled: #{uncompiled.map(&:name).join(', ')}" if uncompiled.any? && !options[:only]
	else
		abort "Compiled although disabled: #{compiled.map(&:name).join(', ')}" if compiled.any?
	end
end

if options[:digest]
	scenarios.each do |name, scenario|
		output = scenario.call
		puts "#{name.ljust(16)} #{output.bytesize.to_s.rjust(8)} bytes  #{Digest::SHA256.hexdigest(output)[0, 16]}"
	end
	exit
end

def allocations(scenario, iterations: 20)
	scenario.call
	GC.start
	GC.disable
	before = GC.stat(:total_allocated_objects)
	iterations.times { scenario.call }
	allocated = GC.stat(:total_allocated_objects) - before
	GC.enable
	allocated.fdiv(iterations).round(1)
end

report = Benchmark.ips(quiet: !!options[:json]) do |x|
	x.config(time: options[:time], warmup: options[:warmup])
	scenarios.each { |name, scenario| x.report(name, &scenario) }
end

results = report.entries.to_h do |entry|
	ips = entry.stats.central_tendency
	size = bytes.fetch(entry.label)

	result = {
		ips: ips.round(1),
		error_percent: (100.0 * entry.stats.error / ips).round(2),
		bytes: size,
		gbps: (size * ips * 8 / 1e9).round(3),
		allocations: allocations(scenarios.fetch(entry.label)),
	}

	[entry.label, result]
end

meta = {
	phlex: version,
	compile: three && options[:compile],
	native:,
	yjit: !!(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?),
	ruby: RUBY_DESCRIPTION,
}

if options[:json]
	File.write(options[:json], JSON.pretty_generate(**meta, results:))
else
	puts meta.inspect
	puts "#{'scenario'.ljust(16)} #{'bytes'.rjust(8)} #{'i/s'.rjust(10)} #{'±%'.rjust(6)} #{'Gbit/s'.rjust(8)} #{'objects'.rjust(9)}"
	results.each do |name, r|
		puts "#{name.ljust(16)} #{r[:bytes].to_s.rjust(8)} #{r[:ips].to_s.rjust(10)} #{r[:error_percent].to_s.rjust(6)} #{r[:gbps].to_s.rjust(8)} #{r[:allocations].to_s.rjust(9)}"
	end
end
