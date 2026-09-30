# frozen_string_literal: true

module EquivalenceCases
	module Rescue
		class Rescue < Phlex::HTML
			def view_template
				[1, 2].each do |i|
					li { i }
					raise "in each" if i == 2
				rescue RuntimeError => e
					plain e.message
				end

				begin
					div { raise "oops" }
				rescue
					plain "x"
				end
			end
		end
	end
end
