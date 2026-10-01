# frozen_string_literal: true

module EquivalenceCases
	module PlainForwardedBlock
		class BlockConversion
			def initialize(view, fail: false)
				@view = view
				@fail = fail
			end

			def to_proc
				@view.events << :to_proc
				raise "converting the block failed" if @fail

				proc { raise "plain must not yield" }
			end
		end

		class PlainForwardedBlock < Phlex::HTML
			attr_reader :events

			def initialize(mode = :proc)
				@mode = mode
				@events = []
			end

			def view_template
				begin
					plain "<text>", &build_block
				rescue Phlex::ArgumentError => error
					@events << error.message
				end
				begin
					plain :symbol, &build_block
				rescue Phlex::ArgumentError => error
					@events << error.message
				end
				begin
					plain nil, &build_block
				rescue Phlex::ArgumentError => error
					@events << error.message
				end
				begin
					plain "interpolated #{interpolation}", &build_block
				rescue Phlex::ArgumentError => error
					@events << error.message
				end
				begin
					plain("literal block") { raise "plain must not yield" }
				rescue Phlex::ArgumentError => error
					@events << error.message
				end
				span { "after" }
			end

			def interpolation
				@events << :interpolation
				"<value>"
			end

			def build_block
				@events << :build_block
				span { "side effect" }
				case @mode
				when :proc then proc { raise "plain must not yield" }
				when :conversion then BlockConversion.new(self)
				when :conversion_error then BlockConversion.new(self, fail: true)
				when :nil then nil
				when :raise then raise "building the block failed"
				when :invalid then Object.new
				end
			end

			def self.equivalence_scenarios
				[:proc, :conversion, :conversion_error, :nil, :raise, :invalid].each_with_object({}) do |mode, scenarios|
					[false, true].each do |skipped|
						scenarios["#{mode}, skipped: #{skipped}"] = -> (klass) do
							view = klass.new(mode)
							buffer = +""
							begin
								view.call(buffer, fragments: skipped ? [:missing] : nil)
							rescue RuntimeError, TypeError => error
								failure = [error.class, error.message]
							end
							[buffer, view.events, failure]
						end
					end
				end
			end
		end
	end
end
