# frozen_string_literal: true

# phlex-rails overrides `State#buffer` to write into the Rails output buffer,
# so every write must go through the accessor rather than `@buffer`.
class BufferOverrideTest < Quickdraw::Test
	class RedirectedState < Phlex::SGML::State
		def redirected = (@redirected ||= +"")
		def buffer = redirected
	end

	class Example < Phlex::HTML
		def view_template
			div { raw(safe("<b>raw</b>")) }
			div { safe("<i>safe</i>") }
			div { span { "a" }; "ignored" }
			p { "implicit" }
		end
	end

	test "raw, safe and implicit output go through an overridden buffer" do
		state = RedirectedState.new(output_buffer: +"", fragments: nil)
		Example.new.internal_call(state:)

		assert_equal state.redirected, Example.new.call
		assert_equal state.redirected, %(<div><b>raw</b></div><div><i>safe</i></div><div><span>a</span></div><p>implicit</p>)
	end
end
