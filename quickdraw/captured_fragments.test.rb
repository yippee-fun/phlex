# frozen_string_literal: true

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
