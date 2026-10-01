# frozen_string_literal: true

module EquivalenceCases
	module LambdaSourceFile
		class LambdaSourceFile < Phlex::HTML
			def view_template
				span { -> { __FILE__ }.call }
				span { -> { -> { __FILE__ }.call }.call }
				span { ->(path = __FILE__) { path }.call }
				span { ->(path: __FILE__) { path }.call }
				span { -> { File.read(__FILE__, 29) }.call }
				-> { span { __FILE__ }; plain __FILE__ }.call
			end
		end
	end
end
