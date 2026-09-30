# frozen_string_literal: true

module EquivalenceCases
	module ControlFlow
		class ControlFlow < Phlex::HTML
			def self.equivalence_scenarios = { "empty and false" => -> (klass) { klass.new(items: [], flag: false).call } }

			def initialize(items: [1, 2, 3], flag: true)
				@items = items
				@flag = flag
			end

			def view_template
				if @flag
					div { "if" }
				else
					div { "else" }
				end
				unless @flag
					div { "unless" }
				end
				case @items.length
				in 3 then p { "three" }
				in Integer => n then p { "n=#{n}" }
				end
				ul { @items.each { |i| li { i } } }
				ul { [1, 2].each { |i| li { i } } }
				more.map { |i| li { i } }
				i = 0
				while i < 2
					span { i }
					i += 1
				end
				return if @items.empty?
				footer { "end" }
			end

			def more = [3]
		end
	end
end
