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

	class TickRecorder < Phlex::TUI
		def initialize
			@tick_count = 0
			@last_dt = nil
		end

		attr_reader :tick_count
		attr_reader :last_dt

		def view_template
			paragraph("tick")
		end

		def tick(dt)
			@tick_count += 1
			@last_dt = dt
		end
	end

	class DoubleRenderHost < Phlex::TUI
		def initialize(child)
			@child = child
		end

		def view_template
			render(@child)
			render(@child)
		end
	end

	class TickLifecycleApp < Phlex::TUI::App
		def initialize(root:)
			@root = root
		end

		def view_template
			render(@root)
		end
	end

	private def render_frame(app, dt: 0.016)
		app.instance_variable_set(:@component_tick_dt, dt)
		app.__send__(:render_lines, width: 20, height: 2)
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
		app = QueueSchedulerApp.new
		app.instance_variable_set(:@stdout, stdout)
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
		app = QueueSchedulerApp.new
		app.instance_variable_set(:@stdout, stdout)
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

	test "component tick runs after each frame render" do
		child = TickRecorder.new
		host = Class.new(Phlex::TUI) do
			def initialize(component)
				@component = component
			end

			def view_template
				render(@component)
			end
		end.new(child)
		app = TickLifecycleApp.new(root: host)

		render_frame(app, dt: 0.010)
		assert_equal 1, child.tick_count
		assert_equal 0.010, child.last_dt

		render_frame(app, dt: 0.125)
		assert_equal 2, child.tick_count
		assert_equal 0.125, child.last_dt
	end

	test "component rendered multiple times ticks once" do
		child = TickRecorder.new
		app = TickLifecycleApp.new(root: DoubleRenderHost.new(child))

		render_frame(app, dt: 0.050)
		assert_equal 1, child.tick_count
		assert_equal 0.050, child.last_dt
	end
end
