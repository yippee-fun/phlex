#!/usr/bin/env ruby
# frozen_string_literal: true

# Alternates runs of bench.rb across configurations and keeps each one's best run per scenario.
#
#   ruby compare.rb --phlex-2 PATH/lib --phlex-3 PATH/lib --phlex-3-ruby PATH/lib [--fixtures PATH] [--rounds N] [--time SECONDS]
#
# --phlex-3 is a lib with the compiled C extension; --phlex-3-ruby is one without lib/phlex_native.
# Neither may be the lib Bundler puts on the load path through the gemspec, or that one's extension loads too.

require "optparse"
require "json"
require "tmpdir"

options = { rounds: 3, time: 3.0 }

OptionParser.new do |parser|
	parser.on("--phlex-2 PATH") { |value| options[:phlex_2] = value }
	parser.on("--phlex-3 PATH") { |value| options[:phlex_3] = value }
	parser.on("--phlex-3-ruby PATH") { |value| options[:phlex_3_ruby] = value }
	parser.on("--fixtures PATH") { |value| options[:fixtures] = value }
	parser.on("--rounds N", Integer) { |value| options[:rounds] = value }
	parser.on("--time SECONDS", Float) { |value| options[:time] = value }
end.parse!

CONFIGS = {
	"2.4.3" => [options.fetch(:phlex_2), ["--no-compile"]],
	"3.0 runtime" => [options.fetch(:phlex_3_ruby), ["--no-compile"]],
	"3.0 runtime + native" => [options.fetch(:phlex_3), ["--no-compile"]],
	"3.0 compiled" => [options.fetch(:phlex_3_ruby), []],
	"3.0 compiled + native" => [options.fetch(:phlex_3), []],
}.freeze

runner = File.expand_path("bench.rb", __dir__)
runs = CONFIGS.transform_values { [] }
meta = {}

Dir.mktmpdir do |directory|
	options[:rounds].times do |round|
		CONFIGS.each_with_index do |(name, (lib, flags)), index|
			path = File.join(directory, "#{round}-#{index}.json")
			command = [RbConfig.ruby, "--yjit", runner, "--json", path, "--time", options[:time].to_s, *flags]
			warn "round #{round + 1}/#{options[:rounds]}: #{name}"
			system({ "PHLEX_LIB" => lib, "FIXTURES" => options[:fixtures] }.compact, *command, exception: true)
			data = JSON.parse(File.read(path))
			abort "#{name} loaded the C extension" if name.include?("3.0") && data["native"] != name.end_with?("native")
			meta[name] = data.except("results")
			runs[name] << data.fetch("results")
		end
	end
end

best = runs.transform_values do |config_runs|
	config_runs.each_with_object({}) do |run, best|
		run.each { |scenario, result| best[scenario] = result if !best[scenario] || result["ips"] > best[scenario]["ips"] }
	end
end

File.write(File.expand_path("results.json", __dir__), JSON.pretty_generate(meta:, best:))

base = best.fetch("2.4.3")

puts meta.values.first["ruby"]
puts

base.each_key do |scenario|
	puts "#{scenario} (#{base[scenario]['bytes']} bytes)"
	puts "  #{'config'.ljust(24)} #{'i/s'.rjust(10)} #{'Gbit/s'.rjust(8)} #{'objects'.rjust(9)} #{'vs 2.4.3'.rjust(9)}"
	best.each do |name, results|
		r = results.fetch(scenario)
		puts "  #{name.ljust(24)} #{r['ips'].round.to_s.rjust(10)} #{format('%.2f', r['gbps']).rjust(8)} #{r['allocations'].to_s.rjust(9)} #{format('%.2fx', r['ips'] / base[scenario]['ips']).rjust(9)}"
	end
	puts
end
