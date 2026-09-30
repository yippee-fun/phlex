# frozen_string_literal: true

module EquivalenceCases
	module PerKeyAttributes
		class Values < Phlex::HTML
			ToHash = Struct.new(:x, :y) do
				def to_h = { x:, y: }
			end

			def initialize
				@string = 'a"b'
				@symbol = :snake_case
				@integer = 1
				@float = 1.5
				@true = true
				@false = false
				@nil = nil
				@array = ["a", :b, 1, nil, ["c", :d]]
				@set = Set["a", :b]
				@hash = { x: 1, "y" => "z", _: "root", nested: { deep: true } }
				@styles = { color: "red", "font-size" => "1px", top: nil }
				@style_list = ["color: red", "top: 0;", { left: 1 }]
				@to_hash = ToHash.new(1, "two")
				@date = Date.new(2020, 1, 2)
			end

			def view_template
				div(class: @string, id: "static", data: @hash) { "mixed" }
				span("data-x" => @integer, class: @symbol, title: @float)
				span(class: "static", title: @float, id: @string)
				input(type: "checkbox", checked: @true, disabled: @false, hidden: @nil, name: @string)
				div(class: @array, data_set: @set)
				div(style: @styles)
				div(style: @style_list)
				div(style: @string)
				div(class: safe("<b>"), onclick: safe("alert(1)"))
				div(data: @to_hash, title: @date)
				div(class: @string, "class" => "string key") # rubocop:disable Style/HashSyntax
				img(src: "/a.png", alt: @string)
				input(type: "text", name: @string, value: @string)
				div(class: "btn #{@symbol}", id: "id-#{@string}", title: "#{@integer}") { "interpolated" } # rubocop:disable Style/RedundantInterpolation
				a(href: "/users/#{@integer}", class: "link #{@string}") { "reference" }
				div(class: "btn #{@string}", id: dom_id)
			end

			def dom_id = "generated"
		end

		class References < Phlex::HTML
			def self.equivalence_scenarios
				{
					"safe" => -> (klass) { klass.new("/ok?a=1&b=2").call },
					"javascript" => -> (klass) { klass.new("javascript:alert(1)").call },
					"obscured" => -> (klass) { klass.new("JAVA\tscript:alert(1)").call },
					"encoded" => -> (klass) { klass.new("&#106;avascript:alert(1)").call },
					"named entity" => -> (klass) { klass.new("java&Tab;script:alert(1)").call },
					"quoted" => -> (klass) { klass.new('/ok"').call },
					"true" => -> (klass) { klass.new(true).call },
					"nil" => -> (klass) { klass.new(nil).call },
					"integer" => -> (klass) { klass.new(1).call },
					"hash" => -> (klass) { klass.new({ a: 1 }).call },
				}
			end

			def initialize(href)
				@href = href
			end

			def view_template
				a(href: @href, class: "link") { "link" }
				a(href: safe(@href.to_s)) { "safe" }
				img(src: @href, alt: "image")
				form(action: @href, method: "post")
			end
		end

		class Errors < Phlex::HTML
			def initialize
				@bad = Object.new
				@raising = Object.new.tap { |object| def object.to_h = raise("bad to_h") }
			end

			def view_template
				begin
					div(id: "static", class: @bad)
				rescue Phlex::ArgumentError
					plain "rescued after static"
				end

				begin
					div(class: @bad, id: "static") { "content" }
				rescue Phlex::ArgumentError
					plain "rescued before static"
				end

				begin
					div(class: "ok", data: @raising, id: @bad)
				rescue RuntimeError => e
					plain e.message
				end

				begin
					div("data-bad name" => @bad)
				rescue Phlex::ArgumentError
					plain "rescued name"
				end

				begin
					div("id" => "string") # rubocop:disable Style/HashSyntax
				rescue Phlex::ArgumentError
					plain "rescued string id"
				end
			end
		end

		class EvaluationOrder < Phlex::HTML
			def initialize
				@flag = true
				@log = []
			end

			def view_template
				div(class: @flag, id: flip, title: @flag, "data-a" => flip, lang: @flag)
				div(class: @flag ? "on" : "off", id: flip)
				div(class: log("a"), id: log("b")) { "order" }
				plain @log.join(",")
			end

			def flip
				@flag = !@flag
				@flag.to_s
			end

			def log(name)
				@log << name
				name
			end
		end
	end
end
