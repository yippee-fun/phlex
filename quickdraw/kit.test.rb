# frozen_string_literal: true

class KitTest < Quickdraw::Test
	require "components"
	require "sgml_helper"
	include SGMLHelper

	class Example < Phlex::HTML
		include Components

		def view_template
			SayHi("Joel", times: 2) { "Inside" }
			Components::SayHi("Will", times: 1) { "Inside" }
		end
	end

	class Components::Title < Phlex::HTML
		def view_template
			h1 { "Hello, world" }
		end

		def render?
			false
		end
	end

	class Components::Subtitle < Phlex::HTML
		def view_template
			h2 { "Welcome" }
		end
	end

	class Page < Phlex::HTML
		include Components

		def view_template
			Components::Title()

			Components::Subtitle()
		end
	end

	test "raises when you try to render a component outside of a rendering context" do
		error = assert_raises(RuntimeError) { Components::SayHi("Joel") }
		assert_equal error.message, "You can't call `SayHi' outside of a Phlex rendering context."
	end

	test "defines methods for its components" do
		assert_equal Example.new.call, %(<article><h1>Hi Joel</h1><h1>Hi Joel</h1>Inside</article><article><h1>Hi Will</h1>Inside</article>)
	end

	test "nested kits" do
		assert_equal phlex { Components::Foo::Bar() }, "<h1>Bar</h1>"
	end

	# Github issue: https://github.com/yippee-fun/phlex/issues/979
	test "phlex rendering context" do
		assert_equal Page.call, %(<h2>Welcome</h2>)
	end

	module ShadowingComponents
		extend Phlex::Kit

		class Thread < Phlex::HTML
			def view_template = hr
		end

		class Card < Phlex::HTML
			def view_template = br
		end
	end

	class ShadowingExample < Phlex::HTML
		def view_template
			ShadowingComponents::Card()
		end
	end

	test "a kit with its own Thread constant still finds the rendering context" do
		assert_equal ShadowingExample.call, %(<br>)
	end

	module KeywordComponents
		extend Phlex::Kit

		const_set(:BEGIN, Class.new(Phlex::HTML) { def view_template = hr })
		const_set(:END, Class.new(Phlex::HTML) { def view_template = br })
	end

	class KeywordExample < Phlex::HTML
		include KeywordComponents

		def view_template
			public_send(:BEGIN)
			KeywordComponents.public_send(:END)
		end
	end

	test "components named BEGIN or END get kit methods" do
		assert_equal KeywordExample.call, %(<hr><br>)
	end

	if defined?(::Ractor)
		# No text or attributes, so rendering doesn't depend on ERB::Escape or
		# the attribute cache being usable from a non-main Ractor.
		module RactorComponents
			extend Phlex::Kit

			class Rules < Phlex::HTML
				def initialize(count, with_break: false)
					@count = count
					@with_break = with_break
				end

				def view_template
					section do
						@count.times { hr }
						br if @with_break
						yield
					end
				end
			end
		end

		class RactorExample < Phlex::HTML
			include RactorComponents

			def view_template
				Rules(2, with_break: true) { hr }
			end
		end

		class RactorNamespacedExample < Phlex::HTML
			def view_template
				RactorComponents::Rules(1) { br }
			end
		end

		def run_in_ractor(&)
			experimental = Warning[:experimental]
			Warning[:experimental] = false
			ractor = Ractor.new(&)
			ractor.respond_to?(:value) ? ractor.value : ractor.take
		ensure
			Warning[:experimental] = experimental
		end

		test "kit methods can be called inside a non-main Ractor" do
			assert_equal run_in_ractor { RactorExample.call }, %(<section><hr><hr><br><hr></section>)
		end

		test "namespaced kit methods can be called inside a non-main Ractor" do
			assert_equal run_in_ractor { RactorNamespacedExample.call }, %(<section><hr><br></section>)
		end
	end
end
