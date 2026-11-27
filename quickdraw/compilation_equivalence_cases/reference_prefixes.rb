# frozen_string_literal: true

module EquivalenceCases
	module ReferencePrefixes
		class ReferencePrefixes < Phlex::HTML
			VALUES = [
				"1",
				"javascript:alert(1)",
				"script:alert(1)",
				"&#106;avascript:x",
				%(say "hi"),
				"café&#233;",
				"x&colon;",
				(+"&\xFF").force_encoding(Encoding::UTF_8),
				(+":j\xFF").force_encoding(Encoding::UTF_8),
				"\xFF&#233;".b,
				(+"\xE9&#233;").force_encoding(Encoding::ISO_8859_1),
				"x".encode(Encoding::UTF_16LE),
			].freeze

			def self.equivalence_scenarios
				VALUES.each_with_index.to_h do |value, index|
					["value #{index}", -> (klass) { klass.new(value).call }]
				end.merge("fragment" => -> (klass) { klass.new("x").call(fragments: [:f]) })
			end

			def initialize(value)
				@value = value
			end

			def view_template
				a(href: "/posts/#{@value}") { "post" }
				a(href: "mailto:#{@value}", class: "m")
				img(src: "https://example.com/#{@value}.png")
				a(href: "java#{@value}")
				a(href: "javascript:#{@value}")
				a(href: "javascript:void#{@value}")
				a(href: "#{@value}/page")
				a(href: "/#{@value}")
				a(href: "JaVa&#115;cript:#{@value}")
				a(href: "  Java Script:#{@value}")
				a(href: %(/q"#{@value}))
				a(href: "\xC3#{@value}")
				fragment(:f) { a(href: "/f/#{@value}") }
			rescue => error
				plain "rescued #{error.class}"
			end
		end
	end
end
