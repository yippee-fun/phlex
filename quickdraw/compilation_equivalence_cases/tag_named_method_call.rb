# frozen_string_literal: true

module EquivalenceCases
	module TagNamedMethodCall
		Record = Struct.new(:title, :p, :b)

		class TagNamedMethodCall < Phlex::HTML
			def initialize
				@record = Record.new("Title", "para", "bold")
			end

			def view_template
				h1 { @record.title }
				div { @record.p }
				span { "x".b }
				section { @record.b.then { |b| b.upcase } }
				td { self.class.name.i }
			end
		end
	end
end
