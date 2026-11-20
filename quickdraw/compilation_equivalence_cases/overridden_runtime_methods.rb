# frozen_string_literal: true

module EquivalenceCases
	module OverriddenRuntimeMethods
		class NoBlockGiven < Phlex::HTML
			def view_template
				div { "x" }
				plain "text"
			end

			private def block_given? = false
		end

		class RaisingIdentity < Phlex::HTML
			def view_template
				[1].each { span { "item" } }
			rescue RuntimeError
				plain "rescued"
			end

			def equal?(_other) = raise("identity")
		end

		class CustomText < Phlex::HTML
			def view_template
				plain "x"
			end

			private def __text__(_content) = @_state.buffer << "custom"
		end
	end
end
