# frozen_string_literal: true

module EquivalenceCases
	module SupersededDefinitions
		# Each `def` here is replaced later in the class, so it isn't live and is
		# left alone rather than taken as a sign the file has changed.
		class SupersededDefinitions < Phlex::HTML
			WRITABLE = true

			def initialize
				self.title = "from attr_writer"
				self.name = "from attr_accessor"
				self.rank = "from attr"
				self.level = "from attr with a constant"
			end

			def view_template
				h1 { title }
				h2 { name }
				h3 { rank }
				h4 { level }
				p { subtitle }
				span { label }
			end

			def title = "default"
			attr_reader :title

			def title=(value)
				@title = "default"
			end
			attr_writer :title

			def rank=(value)
				@rank = "default"
			end
			attr :rank, true

			def level=(value)
				@level = "default"
			end
			attr :level, WRITABLE

			def name = "default"
			def name=(value)
				@name = "default"
			end

			attr_accessor :name

			def subtitle = "default"
			define_method(:subtitle) { "from define_method" }

			def heading = "from alias_method"
			def label = "default"
			alias_method :label, :heading
		end
	end
end
