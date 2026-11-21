# frozen_string_literal: true

module EquivalenceCases
	module InlineSvgFallbacks
		# Mixed into Phlex::SVG rather than registered on its standard elements,
		# which other tests enumerate.
		module Elements
			extend Phlex::SGML::Elements

			register_element :stream_head, tag: "head"
			register_element :private_mark
			private :private_mark
		end

		Phlex::SVG.include(Elements)

		class InlineSvgFallbacks < Phlex::HTML
			def self.equivalence_scenarios
				{ "invalid attribute" => -> (klass) { klass.new(invalid: true).call } }
			end

			def initialize(invalid: false)
				@invalid = invalid
			end

			def view_template
				svg do |s|
					s.path
				ensure
					s.circle
				end
				svg { |s| s.stream_head }
				svg { |s| s.path("a\xFF" => 1) } if @invalid
				begin
					svg { |s| s.private_mark }
				rescue NoMethodError
					plain "private"
				end
			rescue ArgumentError, Phlex::ArgumentError
				plain "invalid"
			end
		end

		class InlineSvgRenderOverride < Phlex::HTML
			def view_template
				svg { |s| s.path }
			end

			def render(*, &)
				plain "replacement"
			end
		end
	end
end
