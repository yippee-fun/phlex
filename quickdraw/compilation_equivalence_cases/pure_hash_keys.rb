# frozen_string_literal: true

module EquivalenceCases
	module PureHashKeys
		class RaisingKey
			def hash = raise("hash")
		end

		class PureHashKeys < Phlex::HTML
			def self.equivalence_scenarios
				{ "fragment" => -> (klass) { klass.new.call(fragments: [:missing]) } }
			end

			def view_template
				literal_key
				variable_key
			end

			private def literal_key
				div(RaisingKey.new => nil)
			rescue RuntimeError
				plain "rescued literal"
			end

			private def variable_key
				key = RaisingKey.new
				div(key => nil)
			rescue RuntimeError
				plain "rescued variable"
			end
		end
	end
end
