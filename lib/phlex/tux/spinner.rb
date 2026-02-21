# frozen_string_literal: true

class Phlex::Tux::Spinner < Phlex::TUI
	DEFAULT_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze

	def initialize(frames: DEFAULT_FRAMES, interval: 0.08, label: nil, color: nil, bg: nil, **attributes)
		@frames = normalize_frames(frames)
		@interval = normalize_interval(interval)
		@label = label
		@color = color
		@bg = bg
		@attributes = attributes
		@frame_index = 0
		@elapsed = 0.0
		@running = true
	end

	attr_reader :interval

	def running?
		@running
	end

	def start!
		@running = true
		nil
	end

	def stop!
		@running = false
		nil
	end

	def reset!
		@frame_index = 0
		@elapsed = 0.0
		request_render!
		nil
	end

	def tick(dt)
		return nil unless @running

		if Numeric === dt && dt.positive?
			@elapsed += dt

			while @elapsed >= @interval
				@elapsed -= @interval
				@frame_index += 1
				@frame_index = 0 if @frame_index >= @frames.length
			end
		end

		request_render!
		nil
	end

	def view_template
		attributes = @attributes
		if !@color.nil? || !@bg.nil?
			attributes = attributes.merge(color: @color, bg: @bg)
		end

		box(**attributes) do
			paragraph(trim_trailing_whitespace: false) do
				span(@frames[@frame_index])
				if @label
					span(" ")
					span(@label)
				end
			end
		end
	end

	private def normalize_frames(frames)
		unless Array === frames
			raise ArgumentError, "frames must be an array"
		end

		if frames.empty?
			raise ArgumentError, "frames must not be empty"
		end

		normalized = []
		i = 0
		while i < frames.length
			frame = frames[i]
			normalized << frame.to_s
			i += 1
		end

		normalized
	end

	private def normalize_interval(interval)
		unless Numeric === interval
			raise ArgumentError, "interval must be numeric"
		end

		unless interval.positive?
			raise ArgumentError, "interval must be greater than zero"
		end

		interval.to_f
	end
end
