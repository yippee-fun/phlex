# frozen_string_literal: true

module EquivalenceCases
	module ElementBlockSemantics
		class Breaking < Phlex::HTML
			def view_template
				plain([1].map { div { break "x" } }.join)
				head { break }
				div { |component| 1 }
			end

			def flush = plain("flushed")

			def __send__(name, ...) = (name == :format_object) ? "intercepted" : super
		end

		class ParameterDefaults < Phlex::HTML
			def view_template
				whitespace { |_, x = plain("side")| } # rubocop:disable Lint/EmptyBlock
				div { |_, x = raise("oops")| } # rubocop:disable Lint/EmptyBlock
			rescue RuntimeError
				plain "rescued"
			end
		end

		class CustomImplicitOutput < Phlex::HTML
			def self.equivalence_scenarios
				{ "fragment" => -> (klass) { klass.new.call(fragments: [:missing]) } }
			end

			def view_template
				comment { "hi" }
				whitespace { "there" }
			end

			private def __implicit_output__(_content) = plain("custom")
		end

		class OtherReceiver < Phlex::HTML
			def view_template
				comment { span }
			rescue NameError
				plain "rescued"
			end

			private def __yield_content__(&) = Object.new.instance_exec(&)
		end
	end
end
