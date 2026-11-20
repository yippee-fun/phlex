# frozen_string_literal: true

module EquivalenceCases
	module GuardedBlockIdentity
		# Claims to be anything it's compared with.
		class Impostor
			attr_reader :calls

			def equal?(_) = true
			def br = (@calls ||= []) << :br
		end

		class ImpostorReceiver < Phlex::HTML
			def view_template
				h1 { "Title" }
				impostor = Impostor.new
				impostor.instance_exec(&block_of { br })
				plain impostor.calls.inspect
			end

			def block_of(&block) = block
		end

		class Receiver
			attr_reader :calls

			def br = (@calls ||= []) << :br
		end

		# Claims every receiver is itself.
		class TrustingComponent < Phlex::HTML
			def equal?(_) = true

			def view_template
				h1 { "Title" }
				receiver = Receiver.new
				receiver.instance_exec(&block_of { br })
				plain receiver.calls.inspect
			end

			def block_of(&block) = block
		end
	end
end
