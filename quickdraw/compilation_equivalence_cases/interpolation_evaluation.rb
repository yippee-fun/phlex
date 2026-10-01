# frozen_string_literal: true

module EquivalenceCases
	module InterpolationEvaluation
		# Records when it's converted to a string, and can be made to raise.
		class Loud
			def initialize(log, raise: false)
				@log = log
				@raise = raise
			end

			def to_s
				@log << "to_s"
				raise "loud" if @raise

				"loud"
			end
		end

		class InterpolationEvaluation < Phlex::HTML
			def self.equivalence_scenarios
				{
					"fragment b" => -> (klass) { klass.new.call(fragments: [:b]) },
					"raising" => -> (klass) { klass.new(raising: true).call },
				}
			end

			def initialize(raising: false)
				@log = []
				@loud = Loud.new(@log, raise: raising)
			end

			def view_template
				fragment(:a) { div { "a" } }
				div { "#{@loud}" }
				plain "p #{@loud}"
				div(title: "t #{@loud}")
				span { "#{@loud} #{@loud}" }
				fragment(:b) { div { @log.join(",") } }
			end
		end
	end
end
