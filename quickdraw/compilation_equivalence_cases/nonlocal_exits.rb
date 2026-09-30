# frozen_string_literal: true

module EquivalenceCases
	module NonlocalExits
		class NonlocalExits < Phlex::HTML
			def view_template
				catch(:done) { div { throw :done } }
				plain "after throw"

				ul do
					[1, 2, 3].each do |i|
						li do
							break if i == 2

							plain i.to_s
						end
					end
				end

				early_return
				plain "after return"

				section do
					[1, 2].each do |i|
						p do
							next if i == 1

							plain i.to_s
						end
					end
				end
			end

			def early_return
				div { return if @items.nil? }
				plain "unreachable"
			end
		end
	end
end
