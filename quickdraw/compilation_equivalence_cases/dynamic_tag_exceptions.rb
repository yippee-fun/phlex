# frozen_string_literal: true

module EquivalenceCases
	module DynamicTagExceptions
		class HTML < Phlex::HTML
			def view_template
				[:div, :custom_tag, :svg].each do |name|
					[{}, { id: "example" }].each do |attributes|
						begin
							tag(name, **attributes) do |content|
								content.plain "before"
								raise "example"
							end
						rescue RuntimeError
							span { "after" }
						end
					end
				end
			end
		end

		class SVG < Phlex::SVG
			def view_template
				[:g, :custom_tag].each do |name|
					[{}, { id: "example" }].each do |attributes|
						begin
							tag(name, **attributes) do |content|
								content.plain "before"
								raise "example"
							end
						rescue RuntimeError
							text { "after" }
						end
					end
				end
			end
		end
	end
end
