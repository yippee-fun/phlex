# frozen_string_literal: true

class TUISpinnerTest < Quickdraw::Test
	class FakeApp
		def initialize
			@render_requests = 0
		end

		attr_reader :render_requests

		def request_render!
			@render_requests += 1
		end

		def runtime
			nil
		end
	end

	private def render_text(component, width: 20, height: 1)
		tree = component.call(Phlex::TUI::Tree.new)
		renderer = Phlex::TUI::Render.new(tree, width:, height:)
		renderer.call.gsub(/\e\[[\d;]*m/, "")
	end

	test "spinner advances frames and requests render" do
		app = FakeApp.new
		spinner = Phlex::Tux::Spinner.new(frames: ["-", "\\", "|", "/"], interval: 0.1)
		spinner.call(context: app)

		assert_equal 0, app.render_requests
		assert_equal "-", render_text(spinner).strip

		spinner.tick(0.05)
		assert_equal 1, app.render_requests
		assert_equal "-", render_text(spinner).strip

		spinner.tick(0.05)
		assert_equal 2, app.render_requests
		assert_equal "\\", render_text(spinner).strip

		spinner.tick(0.2)
		assert_equal 3, app.render_requests
		assert_equal "/", render_text(spinner).strip
	end

	test "spinner validates frames and interval" do
		error = assert_raises(ArgumentError) { Phlex::Tux::Spinner.new(frames: []) }
		assert_equal "frames must not be empty", error.message

		error = assert_raises(ArgumentError) { Phlex::Tux::Spinner.new(interval: 0) }
		assert_equal "interval must be greater than zero", error.message
	end
end
