# frozen_string_literal: true

module EquivalenceCases
	module ConditionalValues
		class ConditionalValues < Phlex::HTML
			def self.equivalence_scenarios
				{
					"inactive" => -> (klass) { klass.new(active: false).call },
					"nil name" => -> (klass) { klass.new(name: nil).call },
				}
			end

			def initialize(active: true, name: "<name>")
				@active = active
				@name = name
			end

			def view_template
				div(class: @active ? "on" : "off") { "ternary" }
				div(class: active? ? "on" : "off") { "method predicate" }
				div(class: (@active ? "on" : nil), id: "static")
				div(class: @active ? "on" : "off", id: dom_id)
				div(class: @active && "on")
				div(class: @name || "anonymous")
				div(class: (@active ? "a" : "b") && (@name || "c"))
				div(class: @active ? (@name ? "named" : "anonymous") : "off")
				div(class: @active ? (active? ? "named" : "anonymous") : "off")
				div(class: (plain("before"); @active) ? "on" : "off")
				div(hidden: @active ? true : nil, tabindex: @active ? 0 : -1)
				a(href: @active ? "javascript:alert(1)" : "/ok") { "guarded" }
				div(class: if @active then "on" end)
				div(class: unless @active then "off" end)
				div(class: if @active then "on" elsif @name then "named" else "off" end)
				div(class: ("on" if @active))
				div(class: ("off" unless @active), id: dom_id)
				div(class: @active ? (@name ? "named" : "anonymous") : "off", id: clear_name)
				div(class: (if @active then "on" elsif @name then "named" else "off" end), id: clear_name)

				span { @active ? "on" : "off" }
				span { active? ? "on" : "off" }
				span { @active ? "<on>" : :"<off>" }
				span { @active ? "on" : nil }
				span { @active && "on" }
				span { @name || "anonymous" }
				span { (@active ? "a" : "b") }
				span { @active ? (@name ? "named" : "anonymous") : "off" }
				span { @active ? (active? ? "named" : "anonymous") : "off" }
				span do
					if @active
						"on"
					elsif @name
						"named"
					else
						"off"
					end
				end
				span do
					unless @active
						"off"
					end
				end
				span { (plain("before"); @active) ? "on" : "off" }
				span { @active ? "on" : @name }
				span { "on" if @active }
				span { "off" unless @active }
			end

			def clear_name
				@name = nil
				"cleared"
			end

			def active? = @active

			def dom_id = "generated"
		end
	end
end
