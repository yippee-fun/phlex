# frozen_string_literal: true

module EquivalenceCases
	module RenderAndLayouts
		class Layout < Phlex::HTML
			def view_template
				html { body { main { yield } } }
			end
		end

		class CaptureLayout < Phlex::HTML
			def view_template
				content = capture { yield }
				div(class: "wrap") { raw safe(content) }
				footer { "len=#{content.bytesize}" }
			end
		end

		class Page < Phlex::HTML
			def view_template
				render Layout.new { div { "page" } }
				render CaptureLayout.new { p { "captured" } }
				render(CaptureLayout.new) { "plain text" }
			end
		end

		class CaptureSelf < Phlex::HTML
			def self.equivalence_scenarios = { "with block" => -> (klass) { klass.new.call { |c| c.span { "y" } } } }

			def view_template
				s = capture { yield }
				pre { s }
			end
		end
	end
end
