#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares two `lib` directories by alternating runs of benchmarks/runtime.rb and keeping each side’s best run.
#
#   bundle exec ruby benchmarks/compare.rb BASE_LIB HEAD_LIB [--rounds N] [--only REGEXP] [--time SECONDS] [--no-yjit | --yjit-only]

require "optparse"
require "json"
require "tmpdir"

options = { rounds: 3, time: 2.0, modes: [false, true] }

OptionParser.new do |parser|
	parser.on("--rounds N", Integer) { |value| options[:rounds] = value }
	parser.on("--only REGEXP") { |value| options[:only] = value }
	parser.on("--time SECONDS", Float) { |value| options[:time] = value }
	parser.on("--no-yjit") { options[:modes] = [false] }
	parser.on("--yjit-only") { options[:modes] = [true] }
end.parse!

base_lib, head_lib = ARGV
raise "Usage: compare.rb BASE_LIB HEAD_LIB" unless base_lib && head_lib

runner = File.expand_path("runtime.rb", __dir__)

def best(runs)
	runs.each_with_object({}) do |run, best|
		run.each do |name, result|
			current = best[name]
			best[name] = result if !current || result["ips"] > current["ips"]
		end
	end
end

options[:modes].each do |yjit|
	runs = { base_lib => [], head_lib => [] }

	Dir.mktmpdir do |directory|
		options[:rounds].times do |round|
			runs.each_key do |lib|
				path = File.join(directory, "#{round}-#{runs.keys.index(lib)}.json")
				command = [RbConfig.ruby]
				command << "--yjit" if yjit
				command.push(runner, "--json", path, "--time", options[:time].to_s)
				command.push("--only", options[:only]) if options[:only]
				system({ "PHLEX_LIB" => lib }, *command, exception: true)
				runs[lib] << JSON.parse(File.read(path)).fetch("results")
			end
		end
	end

	base = best(runs[base_lib])
	head = best(runs[head_lib])

	puts
	puts "YJIT #{yjit ? 'on' : 'off'} (best of #{options[:rounds]})"
	puts "#{'scenario'.ljust(28)} #{'base µs'.rjust(9)} #{'head µs'.rjust(9)} #{'time'.rjust(7)} #{'base obj'.rjust(9)} #{'head obj'.rjust(9)} #{'objects'.rjust(8)}"

	base.each do |name, before|
		after = head.fetch(name)
		before_time = 1_000_000 / before["ips"]
		after_time = 1_000_000 / after["ips"]
		time_change = 100.0 * (after_time - before_time) / before_time
		before_objects = before["allocations"]
		after_objects = after["allocations"]
		object_change = before_objects.zero? ? 0.0 : 100.0 * (after_objects - before_objects) / before_objects

		puts "#{name.ljust(28)} #{before_time.round(1).to_s.rjust(9)} #{after_time.round(1).to_s.rjust(9)} #{format('%+.1f%%', time_change).rjust(7)} #{before_objects.to_s.rjust(9)} #{after_objects.to_s.rjust(9)} #{format('%+.1f%%', object_change).rjust(8)}"
	end
end
