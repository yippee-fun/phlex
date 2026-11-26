# frozen_string_literal: true

module EquivalenceCases
	module ExpectedConstants
		NAMESPACED = :namespaced

		module Theme
			COLOR = "blue<"
		end

		# Reassigns a constant for one render, then puts it back.
		def self.with_constant(owner, name, value)
			original = owner.const_get(name, false)
			owner.send(:remove_const, name)
			owner.const_set(name, value)
			yield
		ensure
			owner.send(:remove_const, name) if owner.const_defined?(name, false)
			owner.const_set(name, original)
		end

		class Base < Phlex::HTML
			INHERITED = "inherited"
			SHADOWED = "from the superclass"
		end

		SHADOWED = "lexical"

		class Literals < Base
			LABEL = "Save & <go>"
			COUNT = 3
			RATIO = 1.5
			KIND = :a_kind
			NONE = nil
			YES = true

			def self.equivalence_scenarios
				{
					"fragment" => -> (klass) { klass.new.call(fragments: [:f]) },
					"reassigned" => -> (klass) { ExpectedConstants.with_constant(klass, :LABEL, "changed") { klass.new.call } },
					"reassigned to a mutable string" => -> (klass) { ExpectedConstants.with_constant(klass, :LABEL, +"Save & <go>") { klass.new.call } },
					"reassigned to a safe string" => -> (klass) { ExpectedConstants.with_constant(klass, :LABEL, Phlex::SGML::SafeValue.new("<b>")) { klass.new.call } },
					"reassigned in a namespace" => -> (klass) { ExpectedConstants.with_constant(Theme, :COLOR, "red") { klass.new.call } },
					"number reassigned" => -> (klass) { ExpectedConstants.with_constant(klass, :COUNT, 3.0) { klass.new.call } },
				}
			end

			def view_template
				span { "before" }
				div { LABEL }
				div { COUNT }
				div { RATIO }
				div { KIND }
				div { NONE }
				div { YES }
				div { Theme::COLOR }
				div { ExpectedConstants::Theme::COLOR }
				div { ::EquivalenceCases::ExpectedConstants::NAMESPACED }
				div { INHERITED }
				div { SHADOWED }
				div { span { LABEL } }
				fragment(:f) { p { COUNT } }
				plain LABEL
				plain COUNT
				span { "after" }
			end
		end

		class NotLiterals < Phlex::HTML
			MUTABLE = +"mutable"
			COMPUTED = ("comp" + "uted").freeze
			BIG = 2 ** 80
			HEAP_FLOAT = 1e300
			SAFE = Phlex::SGML::SafeValue.new("<b>safe</b>")
			SUBCLASS = Class.new(String).new("subclass").freeze
			EXTENDED = (+"<i>extended</i>").extend(Phlex::SGML::SafeObject).freeze

			def view_template
				div { MUTABLE }
				div { COMPUTED }
				div { BIG }
				div { HEAP_FLOAT }
				div { SAFE }
				div { SUBCLASS }
				div { EXTENDED }
			end
		end

		class Missing < Phlex::HTML
			def self.equivalence_scenarios
				{
					"defined later" => -> (klass) do
						klass.const_set(:LATER, "later")
						klass.new.call
					ensure
						klass.send(:remove_const, :LATER)
					end,
				}
			end

			def view_template
				div { LATER }
			end
		end

		class Removed < Phlex::HTML
			GONE = "gone"

			def self.equivalence_scenarios
				{ "removed" => -> (klass) { ExpectedConstants.with_constant(klass, :GONE, "x") { klass.send(:remove_const, :GONE) && klass.new.call } } }
			end

			def view_template
				div { GONE }
			end
		end

		class FormattedNumbers < Phlex::HTML
			COUNT = 1

			def view_template
				div { COUNT }
				plain COUNT
			end

			private def format_object(object) = "number #{object}"
		end

		class PlainBoolean < Phlex::HTML
			YES = true

			def view_template
				plain YES
			rescue Phlex::ArgumentError
				plain "rescued"
			end
		end
	end
end
