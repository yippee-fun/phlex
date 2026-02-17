# frozen_string_literal: true

class TUIAppTest < Quickdraw::Test
	class FakeStdout
		def initialize
			@writes = []
		end

		attr_reader :writes

		def tty?
			true
		end

		def winsize
			[24, 80]
		end

		def write(value)
			@writes << value
			value.bytesize
		end

		def flush
		end
	end

	class QueueSchedulerApp < Phlex::TUI::App
		def initialize(...)
			super
			@render_count = 0
		end

		attr_reader :render_count

		def view_template
			paragraph("frame")
		end

		private def render_lines(width:, height:)
			@render_count += 1
			[@render_count.to_s.ljust(width)]
		end
	end

	private def wait_until(timeout: 1.0)
		deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second) + timeout

		until yield
			now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
			raise "timed out waiting" if now > deadline

			sleep(0.01)
		end
	end

	test "initial paint happens then app idles" do
		stdout = FakeStdout.new
		app = QueueSchedulerApp.new(stdout:)
		thread = Thread.new { app.start(fps: 120) }

		wait_until { app.render_count >= 1 }
		sleep(0.15)

		assert_equal 1, app.render_count
	ensure
		app&.stop
		thread&.join(1)
	end

	test "multiple render requests coalesce into one frame" do
		stdout = FakeStdout.new
		app = QueueSchedulerApp.new(stdout:)
		thread = Thread.new { app.start(fps: 30) }

		wait_until { app.render_count >= 1 }

		3.times { app.request_render! }

		wait_until { app.render_count >= 2 }
		sleep(0.2)

		assert_equal 2, app.render_count
	ensure
		app&.stop
		thread&.join(1)
	end
end
