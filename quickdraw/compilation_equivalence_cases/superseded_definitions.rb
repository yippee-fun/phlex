# frozen_string_literal: true

module EquivalenceCases
	module SupersededDefinitions
		# Each `def` here is replaced later in the class, so it isn't live and is
		# left alone rather than taken as a sign the file has changed.
		class SupersededDefinitions < Phlex::HTML
			def initialize
				@title = "from attr_reader"
			end

			def view_template
				h1 { title }
				p { subtitle }
				span { label }
			end

			def title = "default"
			attr_reader :title

			def subtitle = "default"
			define_method(:subtitle) { "from define_method" }

			def heading = "from alias_method"
			def label = "default"
			alias_method :label, :heading
		end
	end
end
