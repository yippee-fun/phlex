# frozen_string_literal: true

module EquivalenceCases
	module PartialOutputOnErrors
		class PartialOutputOnErrors < Phlex::HTML
			def initialize
				@bad = Object.new
				@raising = Object.new.tap { |object| def object.to_s = raise("bad to_s") }
			end

			def view_template
				p { "before" }

				begin
					div(class: @bad)
				rescue Phlex::ArgumentError
					plain "rescued attribute"
				end

				begin
					div { input(onclick: "x") }
				rescue Phlex::ArgumentError
					plain "rescued void child"
				end

				begin
					span { "v#{@raising}" }
				rescue RuntimeError
					plain "rescued interpolation"
				end

				begin
					em { plain "e#{@raising}" }
				rescue RuntimeError
					plain "rescued plain"
				end
			end
		end
	end
end
