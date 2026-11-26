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

	test "a kit's method finds the component of the kit its name now refers to" do
		kit = Module.new { extend Phlex::Kit }
		Object.const_set(:KitTestReloadedKit, kit)
		kit.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })
		page = Class.new(Phlex::HTML) do
			include kit
			def view_template = Card()
		end

		# As a reloader does, which removes the old kit's constants too.
		Object.__send__(:remove_const, :KitTestReloadedKit)
		kit.__send__(:remove_const, :Card)
		reloaded = Module.new { extend Phlex::Kit }
		Object.const_set(:KitTestReloadedKit, reloaded)
		reloaded.const_set(:Card, Class.new(Phlex::HTML) { def view_template = br })

		assert_equal page.call, %(<br>)
	ensure
		Object.__send__(:remove_const, :KitTestReloadedKit) if Object.const_defined?(:KitTestReloadedKit, false)
	end

	test "a kit under a private constant finds its components" do
		outer = Object.const_set(:KitTestPrivateOuter, Module.new)
		kit = outer.const_set(:Kit, Module.new { extend Phlex::Kit })
		kit.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })
		outer.__send__(:private_constant, :Kit)
		page = Class.new(Phlex::HTML) do
			include kit
			def view_template = Card()
		end

		assert_equal page.call, %(<hr>)
	ensure
		Object.__send__(:remove_const, :KitTestPrivateOuter) if Object.const_defined?(:KitTestPrivateOuter, false)
	end

	test "a top-level kit made private finds its components" do
		kit = Object.const_set(:KitTestPrivateKit, Module.new { extend Phlex::Kit })
		kit.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })
		Object.__send__(:private_constant, :KitTestPrivateKit)
		page = Class.new(Phlex::HTML) do
			include kit
			def view_template = Card()
		end

		assert_equal page.call, %(<hr>)
	ensure
		Object.__send__(:remove_const, :KitTestPrivateKit) if Object.const_defined?(:KitTestPrivateKit, false)
	end

	test "a kit's own const_get and methods don't change how it finds its components" do
		kit = Object.const_set(:KitTestCustomisedKit, Module.new)
		kit.define_singleton_method(:const_get) { |name| super(name) }
		kit.define_singleton_method(:named_reference) { |*| "Other" }
		kit.extend(Phlex::Kit)
		kit.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })
		page = Class.new(Phlex::HTML) do
			include kit
			def view_template = Card()
		end

		assert_equal page.call, %(<hr>)
	ensure
		Object.__send__(:remove_const, :KitTestCustomisedKit) if Object.const_defined?(:KitTestCustomisedKit, false)
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

	test "extending a class with Phlex::Kit raises" do
		error = assert_raises(Phlex::ArgumentError) { Class.new.extend(Phlex::Kit) }
		assert_match error.message, /You should only extend modules with `Phlex::Kit`/
	end

	test "an autoloaded component isn't loaded until it's called, from the kit or a component" do
		kit = Module.new { extend Phlex::Kit }
		stub_const("KitTestAutoloadKit", kit)
		dir = tmpdir

		%w[Card Badge Panel].each do |name|
			File.write(File.join(dir, "#{name}.rb"), "class KitTestAutoloadKit::#{name} < Phlex::HTML; def view_template = h1 { #{name.inspect} }; end\n")
			kit.autoload(name.to_sym, File.join(dir, "#{name}.rb"))
		end

		assert kit.autoload?(:Card)
		refute kit.method_defined?(:Card)

		page = Class.new(Phlex::HTML) do
			include kit
			def view_template = Card()
		end

		assert_equal page.call, "<h1>Card</h1>"
		assert_equal Phlex.html { KitTestAutoloadKit::Badge() }, "<h1>Badge</h1>"
		assert page.new.respond_to?(:Panel)
		refute page.new.respond_to?(:Missing)
		refute page.new.respond_to?(:panel)
	end

	test "a kit only answers for its components" do
		kit = Module.new { extend Phlex::Kit }
		kit.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })
		kit.const_set(:Helper, Class.new)
		kit.const_set(:VERSION, "1")
		page = Class.new(Phlex::HTML) { include kit }

		[kit, page.new].each do |receiver|
			assert receiver.respond_to?(:Card)
			refute receiver.respond_to?(:Helper)
			refute receiver.respond_to?(:VERSION)
			refute receiver.respond_to?(:Missing)
			refute receiver.respond_to?(:card)
			assert_raises(NoMethodError) { receiver.Helper }
			assert_raises(NoMethodError) { receiver.Missing }
		end

		refute Phlex::SGML === kit::Helper.allocate
		refute kit::Helper.include?(kit)
	end

	test "a module defined in a kit is a kit" do
		kit = Module.new { extend Phlex::Kit }
		nested = kit.const_set(:Nested, Module.new)
		nested.const_set(:Card, Class.new(Phlex::HTML) { def view_template = hr })

		assert Phlex::Kit === nested
		assert_equal Phlex.html { nested.Card() }, "<hr>"
	end

	test "a kit's component paths are found by name" do
		kit = Module.new { extend Phlex::Kit }
		stub_const("KitTestNamedKit", kit)
		kit.const_set(:Card, Class.new(Phlex::HTML))
		kit.const_set(:Badge, Class.new(Phlex::HTML))

		assert_equal Phlex::Kit.named_path(kit), [:KitTestNamedKit]
		assert_nil Phlex::Kit.named_path(Module.new)
		assert_nil Phlex::Kit.named_path(Module.new.const_set(:Inner, Module.new))
		assert_equal kit.instance_variable_get(:@__phlex_component_paths__), { Card: [:KitTestNamedKit, :Card], Badge: [:KitTestNamedKit, :Badge] }

		Object.__send__(:remove_const, :KitTestNamedKit)
		Object.const_set(:KitTestNamedKit, Module.new)

		assert_nil Phlex::Kit.named_path(kit)
	end

	test "an anonymous kit's BEGIN and END components get methods" do
		kit = Module.new { extend Phlex::Kit }
		kit.const_set(:BEGIN, Class.new(Phlex::HTML) { def view_template = hr })
		kit.const_set(:END, Class.new(Phlex::HTML) { def view_template = br })

		assert_equal Phlex.html { kit.public_send(:BEGIN); kit.public_send(:END) }, "<hr><br>"
	end
end
