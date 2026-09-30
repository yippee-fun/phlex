# frozen_string_literal: true

module EquivalenceCases
	module WhitespaceAndCommentContent
		class Dynamic < Phlex::HTML
			def self.equivalence_scenarios
				{
					"fragment inside whitespace" => -> (klass) { klass.new.call(fragments: ["inner"]) },
					"fragment inside comment" => -> (klass) { klass.new.call(fragments: ["commented"]) },
					"fragment around whitespace" => -> (klass) { klass.new.call(fragments: ["outer"]) },
				}
			end

			def initialize
				@text = "<text>"
				@calls = 0
			end

			def view_template
				whitespace { @text }
				whitespace { helper }
				whitespace { em { helper } }
				whitespace { plain "a"; "ignored" }
				whitespace { |component| component.helper }
				comment { @text }
				comment { helper }
				comment { "Begin #{self.class.name}" }
				comment { plain "a"; "ignored" }
				comment { |component| component.helper }
				comment
				whitespace(&nil)
				comment(&nil)
				whitespace(&proc { helper })
				forwarded = proc { "forwarded" }
				comment(&forwarded)
				whitespace { next "next" }
				comment { next "next" }
				whitespace { break }
				comment { break }
				plain "after break"
				whitespace { fragment("inner") { span { "inner" } } }
				comment { fragment("commented") { "commented" } }
				fragment("outer") { whitespace { span { "outer" } } }
				plain @calls
			end

			def helper
				@calls += 1
				"helper #{@calls}"
			end
		end

		class Errors < Phlex::HTML
			def view_template
				whitespace { raise "whitespace" }
			rescue RuntimeError
				begin
					comment { raise "comment" }
				rescue RuntimeError
					plain "rescued"
				end
			end
		end
	end
end
