# frozen_string_literal: true

module EquivalenceCases
	module GuardedBlockLocals
		class Executor < Phlex::HTML
			def initialize(block)
				@block = block
			end

			def label_text = "executor"
			define_method(:_1) { "executor" }

			# Before Ruby 3.4, `it` in a block is a method call.
			def it = "executor"

			def view_template
				instance_exec("first", "second", &@block)
			end
		end

		class GuardedBlockLocals < Phlex::HTML
			def label_text = "component"
			define_method(:_1) { "component" }

			def view_template
				h1 { "Title" }
				render Executor.new(block_of { br; plain label_text; label_text = "local"; plain label_text })
				render Executor.new(block_of { br; plain({ label_text: }.fetch(:label_text)); label_text = "local" })
				render Executor.new(block_of { br; set = -> { x = "inner" }; x = "outer"; set.call; plain x })
				render Executor.new(block_of { |a = x| br; set = -> { x = "inner" }; x = "outer"; set.call; plain x })
				render Executor.new(block_of { br; set = -> { x = "inner" } if (x = label_text); set.call; plain x })
				render Executor.new(block_of { br; set = ->(arg = (x = "inner")) {}; x = "outer"; set.call; plain x })
				render Executor.new(block_of { br; plain it.to_s; it = "local" })
				render Executor.new(block_of { br; plain({ _1: }.fetch(:_1)); plain _2 })
				render Executor.new(block_of { br; plain label_text })
				block_of { br; plain label_text; label_text = "local"; plain label_text }.call
				render Executor.new(block_of { plain File.basename(__FILE__) })
				render Executor.new(block_of { |_a, _b, path = __FILE__| br; plain File.basename(path) })

				target = Object.new
				definitions = []
				definer = block_of { br; def target.defined_in_block = nil; definitions << target.method(:defined_in_block) }
				definer.call
				render Executor.new(definer)
				plain((definitions[0] == definitions[1]).to_s)

				[
					block_of { |n| br; plain(/#{n}/o.source) },
					block_of { |n| br; def self.once(n) = /#{n}/o.source; plain once(n) },
					block_of { |n| br; plain n.to_s if (n == 1)..(n == 3) }, # rubocop:disable Lint/FlipFlop
					block_of { |n| br; $_ = "1"; plain "hit" if /#{n}/o },
				].each do |stateful|
					stateful.call(1)
					render Executor.new(stateful)
				end
			end

			def block_of(&block) = block
		end
	end
end
