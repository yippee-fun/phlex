# frozen_string_literal: true

require "weakref"

class CapturedFragmentsTest < Quickdraw::Test
	class View < Phlex::HTML
		attr_reader :cache_store

		def initialize(cache_store)
			@cache_store = cache_store
		end

		def view_template(&content)
			low_level_cache("page") { content.call(self) }
		end
	end

	test "captured fragments have offsets at their insertion point on cache misses and hits" do
		content = -> (view) do
			view.instance_exec do
				captured = capture do
					plain "é"
					fragment("piece") { span { "hello" } }
				end
				plain "前"
				raw safe(captured)
			end
		end

		assert_cached_fragments(content, "前é<span>hello</span>", ["piece"], "<span>hello</span>")
	end

	test "nested captures and caches preserve fragment descendants" do
		content = -> (view) do
			view.instance_exec do
				captured = capture do
					fragment("outer") do
						div do
							raw safe(capture do
								low_level_cache("inner") do
									fragment("piece") { span { "hello" } }
								end
							end)
						end
					end
				end
				plain "prefix"
				raw safe(captured)
			end
		end

		assert_cached_fragments(content, "prefix<div><span>hello</span></div>", ["outer", "piece"], "<div><span>hello</span></div>")
		assert_cached_fragments(content, "prefix<div><span>hello</span></div>", ["piece"], "<span>hello</span>")

		store = Phlex::FIFOCacheStore.new
		store.fetch("inner") { ["<span>hello</span>", { "piece" => [0, 18, []] }] }
		assert_equal View.new(store).call(fragments: ["piece"], &content), "<span>hello</span>"
	end

	test "discarded captures do not overwrite enclosing cache fragments" do
		content = -> (view) do
			view.instance_exec do
				fragment("piece") { span { "kept" } }
				capture { fragment("piece") { span { "discarded" } } }
				nil
			end
		end

		assert_cached_fragments(content, "<span>kept</span>", ["piece"], "<span>kept</span>")
	end

	test "an exception in capture restores enclosing cache tracking" do
		content = -> (view) do
			view.instance_exec do
				capture do
					fragment("discarded") { span { "discarded" } }
					raise "capture failed"
				end
			rescue RuntimeError
				fragment("piece") { span { "kept" } }
			end
		end

		assert_cached_fragments(content, "<span>kept</span>", ["piece"], "<span>kept</span>")
		assert_cached_fragments(content, "<span>kept</span>", ["discarded"], "")
	end

	test "equal captured strings keep separate fragment metadata" do
		content = -> (view) do
			view.instance_exec do
				captured = capture { fragment("piece") { span { "hello" } } }
				capture { fragment("discarded") { span { "hello" } } }
				raw safe(captured)
			end
		end

		assert_cached_fragments(content, "<span>hello</span>", ["piece"], "<span>hello</span>")
		assert_cached_fragments(content, "<span>hello</span>", ["discarded"], "")
	end

	test "altered captures do not import stale fragment offsets" do
		content = -> (view) do
			view.instance_exec do
				captured = capture { fragment("piece") { span { "hello" } } }
				captured.replace("<span>other</span>")
				raw safe(captured)
			end
		end

		assert_cached_fragments(content, "<span>other</span>", ["piece"], "")
	end

	test "discarded and flushed captures can be collected while the render state is alive" do
		output = Object.new
		def output.<<(_chunk) = nil
		state = Phlex::SGML::State.new(output_buffer: output, fragments: nil)
		references = temporary_captures(state)

		10.times do
			GC.start
			break if references.count(&:weakref_alive?) < 10
		end

		assert references.count(&:weakref_alive?) < 10
		assert state.should_render?
	end

	test "retained captures keep their fragments across garbage collection and repeated insertion" do
		content = -> (view) do
			view.instance_exec do
				captured = capture { fragment("piece") { span { "hello" } } }
				GC.start
				fragment("outer") do
					div do
						raw safe(captured)
						plain "gap"
						raw safe(captured)
					end
				end
			end
		end

		full = "<div><span>hello</span>gap<span>hello</span></div>"
		assert_cached_fragments(content, full, ["piece"], "<span>hello</span>")
		assert_cached_fragments(content, full, ["outer", "piece"], full)
	end

	test "many captured siblings retain ordered descendants on cache misses and hits" do
		content = -> (view) do
			view.instance_exec do
				fragment("outer") do
					1000.times do |id|
						raw safe(capture { fragment(id.to_s) { span { id } } })
					end
				end
			end
		end

		store = Phlex::FIFOCacheStore.new
		full = View.new(store).call(&content)
		_buffer, fragments = store.fetch("page") { raise "missing cache" }
		assert_equal fragments["outer"][2], (0...1000).map(&:to_s)
		assert_equal View.new(store).call(fragments: ["outer", "999"], &content), full
		assert_equal View.new(store).call(fragments: ["999"], &content), "<span>999</span>"
	end

	[false, true].each do |attributes|
		test "captured fragments returned as safe element content with attributes=#{attributes}" do
			content = -> (view) do
				view.instance_exec do
					div(**(attributes ? { id: "wrapper" } : {})) do
						safe(capture { fragment("piece") { span { "hello" } } })
					end
				end
			end

			full = attributes ? '<div id="wrapper"><span>hello</span></div>' : "<div><span>hello</span></div>"
			assert_cached_fragments(content, full, ["piece"], "<span>hello</span>")
		end
	end

	test "captured fragments returned as safe block content" do
		content = -> (view) do
			view.instance_exec do
				comment { safe(capture { fragment("piece") { span { "hello" } } }) }
			end
		end

		assert_cached_fragments(content, "<!-- <span>hello</span> -->", ["piece"], "<span>hello</span>")
	end

	private def temporary_captures(state)
		Array.new(100) do |id|
			captured = state.capture do
				state.begin_fragment(id)
				state.buffer << ("x" * 1024)
				state.end_fragment(id)
			end
			if id.even?
				state.append(captured)
				state.flush
			end
			WeakRef.new(captured)
		end
	end

	private def assert_cached_fragments(content, full, fragments, selective)
		[false, true].each do |warm|
			store = Phlex::FIFOCacheStore.new
			assert_equal View.new(store).call(&content), full if warm
			2.times do
				assert_equal View.new(store).call(fragments:, &content), selective
			end
			assert_equal View.new(store).call(&content), full
		end
	end
end
