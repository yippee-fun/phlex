# frozen_string_literal: true

class TUIComponentContextTest < Quickdraw::Test
	class FakeApp
		def initialize
			@calls = 0
		end

		attr_reader :calls

		def request_render!
			@calls += 1
		end
	end

	class RequestingComponent < Phlex::TUI
		def view_template
			request_render!
			paragraph("ok")
		end
	end

	test "component request_render! delegates to app context" do
		app = FakeApp.new
		component = RequestingComponent.new

		component.call(context: app)

		assert_equal 1, app.calls
	end
end
