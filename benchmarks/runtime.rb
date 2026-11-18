#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmarks for the non-compiled runtime: time (benchmark-ips) and allocated objects per render.
#
#   bundle exec ruby benchmarks/runtime.rb [--yjit] [--only REGEXP] [--time SECONDS] [--warmup SECONDS] [--json PATH] [--digest]
#
# Set PHLEX_LIB to benchmark another checkout’s `lib` directory with the same scenarios.

require "optparse"
require "json"
require "digest"

options = { time: 2.0, warmup: 1.0 }

OptionParser.new do |parser|
	parser.on("--yjit") { options[:yjit] = true }
	parser.on("--only REGEXP") { |value| options[:only] = Regexp.new(value) }
	parser.on("--time SECONDS", Float) { |value| options[:time] = value }
	parser.on("--warmup SECONDS", Float) { |value| options[:warmup] = value }
	parser.on("--json PATH") { |value| options[:json] = value }
	parser.on("--digest") { options[:digest] = true }
end.parse!

$LOAD_PATH.unshift(File.expand_path(ENV["PHLEX_LIB"])) if ENV["PHLEX_LIB"]

require "phlex"
require "benchmark/ips"

require_relative "../fixtures/page"
require_relative "../fixtures/layout"
require_relative "../fixtures/dynamic_list"

if options[:yjit] && !RubyVM::YJIT.enabled?
	if RubyVM::YJIT.respond_to?(:enable)
		RubyVM::YJIT.enable
	else
		abort "This Ruby can only enable YJIT at startup. Run it with `ruby --yjit`."
	end
end

module RuntimeBenchmark
	Item = Struct.new(:id, :title, :summary, :tag, :path, :dom_id)

	ITEMS = Array.new(100) do |i|
		Item.new(i, "Title #{i}", "Summary <#{i}> & more", "tag-#{i % 7}", "/items/#{i}", "item_#{i}").freeze
	end.freeze

	COUNTER = [0]

	module Kit
		extend Phlex::Kit

		class Badge < Phlex::HTML
			def initialize(label)
				@label = label
			end

			def view_template
				span(class: "badge") { @label }
			end
		end

		class Button < Phlex::HTML
			def initialize(href:, variant: :primary)
				@href = href
				@variant = variant
			end

			def view_template(&)
				a(href: @href, class: ["btn", @variant], &)
			end
		end

		class Card < Phlex::HTML
			def initialize(title:)
				@title = title
			end

			def view_template
				article(class: "card") do
					header(class: "card-header") { h2 { @title } }
					div(class: "card-body") { yield }
				end
			end
		end
	end

	class ComponentsViaRender < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				render Kit::Card.new(title: item.title) do
					render Kit::Badge.new(item.tag)
					p { item.summary }
					render Kit::Button.new(href: item.path) { "Open" }
				end
			end
		end
	end

	class ComponentsViaKit < Phlex::HTML
		include Kit

		def view_template
			ITEMS.each do |item|
				Card(title: item.title) do
					Badge(item.tag)
					p { item.summary }
					Button(href: item.path) { "Open" }
				end
			end
		end
	end

	class ComponentsWithoutBlocks < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				render Kit::Badge.new(item.tag)
				render Kit::Badge.new(item.title)
				render Kit::Badge.new(item.dom_id)
			end
		end
	end

	class StaticAttributes < Phlex::HTML
		def view_template
			100.times do
				div(class: "flex items-center gap-2", id: "row", data_controller: "row") do
					input(type: "text", name: "q", placeholder: "Search", required: true)
					a(href: "/about", class: "link") { "About" }
				end
			end
		end
	end

	class RepeatingAttributes < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				li(id: item.dom_id, class: "item") do
					a(href: item.path) { item.title }
				end
			end
		end
	end

	class UniqueAttributes < Phlex::HTML
		def view_template
			n = (COUNTER[0] += 1)

			ITEMS.each do |item|
				li(id: "item_#{n}_#{item.id}", class: "item") do
					a(href: "/items/#{n}/#{item.id}") { item.title }
				end
			end
		end
	end

	class UniqueURLs < Phlex::HTML
		def view_template
			n = (COUNTER[0] += 1)

			ITEMS.each do |item|
				a(href: "https://example.com/journal/#{n}/#{item.id}") { item.title }
			end
		end
	end

	class ComplexAttributes < Phlex::HTML
		def initialize(unique: false)
			@unique = unique
		end

		def view_template
			n = @unique ? (COUNTER[0] += 1) : 0

			ITEMS.each do |item|
				div(
					class: ["card", ("active" if item.id.even?), :p_4],
					data: { controller: "card", action: "click->card#open", card: { id_value: item.id + n, open: true } },
					style: { color: "red", margin_top: "4px" },
					aria: { label: "Card", hidden: false },
				) do
					a(href: "https://example.com/journal/#{item.id}", class: "link", target: :_blank) { item.title }
					img(src: "/images/#{item.id}.png", srcset: ["/images/#{item.id}.png 1x", "/images/#{item.id}@2x.png 2x"], alt: "")
				end
			end
		end
	end

	class Capture < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				captured = capture do
					strong { item.title }
					span { item.summary }
				end

				div { raw safe(captured) }
			end
		end
	end

	class Vanish < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				vanish { span { item.title } }
				p { item.summary }
			end
		end
	end

	CACHE_STORE = Phlex::FIFOCacheStore.new

	class Cached < Phlex::HTML
		def cache_store
			CACHE_STORE
		end

		def view_template
			ITEMS.each do |item|
				cache(item.id) do
					li do
						h2 { item.title }
						p { item.summary }
					end
				end
			end
		end
	end

	class Fragments < Phlex::HTML
		def view_template
			section do
				ITEMS.each { |item| p(class: "before") { item.summary } }
			end

			fragment("target") do
				ul do
					ITEMS.first(20).each { |item| li(id: item.dom_id) { item.title } }
				end
			end

			section do
				ITEMS.each { |item| p(class: "after") { item.summary } }
			end
		end
	end

	class Streaming < Phlex::HTML
		def view_template
			html do
				head { title { "Streaming" } }

				body do
					ITEMS.each_slice(10) do |items|
						items.each do |item|
							article do
								h2 { item.title }
								p { item.summary }
							end
						end

						flush
					end
				end
			end
		end
	end

	class Text < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				plain item.title
				whitespace
				plain item.id
				whitespace { b { item.tag } }
				comment { item.summary }
			end
		end
	end

	class Tag < Phlex::HTML
		def view_template
			ITEMS.each do |item|
				tag(:h2, class: "title") { item.title }
				tag(:my_element) { item.summary }
				tag(:br)
			end
		end
	end

	class Icon < Phlex::SVG
		def view_template
			svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none") do
				25.times do
					g(stroke: "currentColor", stroke_width: 2) do
						path(d: "M4 6h16M4 12h16M4 18h16")
						circle(cx: 12, cy: 12, r: 3)
					end
				end
			end
		end
	end

	class Report < Phlex::CSV
		def escape_csv_injection? = true

		def row_template(row)
			column "id", row[0]
			column "name", row[1]
			column "email", row[2]
			column "notes", row[3]
			column "amount", row[4]
			column "status", row[5]
		end
	end

	CSV_ROWS = Array.new(3_000) do |i|
		[i, "Person #{i}", "person#{i}@example.com", "Likes commas, and \"quotes\"", i * 1.5, :active].freeze
	end.freeze

	SCENARIOS = {
		"page" => -> { Example::Page.new.call },
		"dynamic_list" => -> { Example::DynamicList.new.call },
		"components_render" => -> { ComponentsViaRender.new.call },
		"components_kit" => -> { ComponentsViaKit.new.call },
		"components_no_blocks" => -> { ComponentsWithoutBlocks.new.call },
		"attributes_static" => -> { StaticAttributes.new.call },
		"attributes_repeating" => -> { RepeatingAttributes.new.call },
		"attributes_unique" => -> { UniqueAttributes.new.call },
		"attributes_unique_urls" => -> { UniqueURLs.new.call },
		"attributes_complex" => -> { ComplexAttributes.new.call },
		"attributes_complex_unique" => -> { ComplexAttributes.new(unique: true).call },
		"capture" => -> { Capture.new.call },
		"vanish" => -> { Vanish.new.call },
		"cache" => -> { Cached.new.call },
		"fragments" => -> { Fragments.new.call(fragments: ["target"]) },
		"streaming" => -> { Streaming.new.call },
		"text" => -> { Text.new.call },
		"tag" => -> { Tag.new.call },
		"svg" => -> { Icon.new.call },
		"csv" => -> { Report.new(CSV_ROWS).call },
	}.freeze

	def self.allocations(scenario, iterations: 20)
		scenario.call
		GC.start
		GC.disable
		before = GC.stat(:total_allocated_objects)
		i = 0
		while i < iterations
			scenario.call
			i += 1
		end
		allocated = GC.stat(:total_allocated_objects) - before
		GC.enable
		allocated.fdiv(iterations).round(1)
	end
end

scenarios = RuntimeBenchmark::SCENARIOS
scenarios = scenarios.select { |name, _| options[:only].match?(name) } if options[:only]

if options[:digest]
	scenarios.each do |name, scenario|
		RuntimeBenchmark::COUNTER[0] = 0
		output = scenario.call
		puts "#{name.ljust(28)} #{output.bytesize.to_s.rjust(8)} bytes  #{Digest::SHA256.hexdigest(output)[0, 16]}"
	end

	exit
end

report = Benchmark.ips(quiet: !!options[:json]) do |x|
	x.config(time: options[:time], warmup: options[:warmup])
	scenarios.each { |name, scenario| x.report(name, &scenario) }
end

results = report.entries.to_h do |entry|
	result = {
		ips: entry.stats.central_tendency.round(1),
		error_percent: (100.0 * entry.stats.error / entry.stats.central_tendency).round(2),
		allocations: RuntimeBenchmark.allocations(scenarios.fetch(entry.label)),
	}

	[entry.label, result]
end

if options[:json]
	File.write(options[:json], JSON.pretty_generate(yjit: RubyVM::YJIT.enabled?, ruby: RUBY_DESCRIPTION, results:))
else
	puts
	puts "#{'scenario'.ljust(28)} #{'i/s'.rjust(10)} #{'µs/i'.rjust(10)} #{'objects/i'.rjust(10)}"
	results.each do |name, result|
		puts "#{name.ljust(28)} #{result[:ips].to_s.rjust(10)} #{(1_000_000 / result[:ips]).round(1).to_s.rjust(10)} #{result[:allocations].to_s.rjust(10)}"
	end
end
