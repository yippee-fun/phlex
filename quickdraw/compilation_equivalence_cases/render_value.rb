# frozen_string_literal: true

module EquivalenceCases
	module RenderValue
		class Child < Phlex::HTML
			def view_template(&)
				span(&)
			end
		end

		class Bare < Phlex::HTML
			def view_template = yield
		end

		class RenderValue < Phlex::HTML
			def view_template
				li { render Child.new }
				li { render(Child.new) { "block value" } }
				li { render(Child.new) { [1, 2].each { |i| break if i == 2 }; "after loop" } }
				li { render(Child.new) { break "broke" } }
				li { render(Bare.new) { break "bare broke" } }
				li { render(Bare.new) { "bare" } }
				li { render { break "nil renderable broke" } }
				li { render { |_, missing = (break "default" if true)| missing } }
				li { render "a string" }
				li { render [Child.new, Child.new] }
				li { render -> { "lambda" } }
				li { render(Child) }
			end
		end

		class OverriddenRender < Phlex::HTML
			def view_template
				li { render Child.new }
			end

			def render(...) = "returned"
		end
	end
end
