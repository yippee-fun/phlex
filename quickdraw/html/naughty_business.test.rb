# frozen_string_literal: true

class NaughtyBusinessTest < Quickdraw::Test
	test "naughty javascript links" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a(href: "javascript:alert(1)") { "a" }
				a(href: "JAVASCRIPT:alert(1)") { "b" }
				a(href: :"JAVASCRIPT:alert(1)") { "c" }
				a(HREF: "javascript:alert(1)") { "d" }
			end
		end

		assert_equal view.call, "<a>a</a><a>b</a><a>c</a><a>d</a>"
	end

	test "naughty uppercase event tag" do
		view = Class.new(Phlex::HTML) do
			def view_template
				button ONCLICK: "ALERT(1)" do
					"naughty button"
				end
			end
		end

		error = assert_raises(ArgumentError) { view.call }
		assert_equal error.message, "Unsafe attribute name detected: ONCLICK."
	end

	test "naughty text" do
		view = Class.new(Phlex::HTML) do
			def view_template
				plain %("><script type="text/javascript" src="bad_script.js"></script>)
			end
		end

		assert_equal view.call, "&quot;&gt;&lt;script type=&quot;text/javascript&quot; src=&quot;bad_script.js&quot;&gt;&lt;/script&gt;"
	end

	test "naughty tag attribute values" do
		view = Class.new(Phlex::HTML) do
			def view_template
				article id: %("><script type="text/javascript" src="bad_script.js"></script>)
			end
		end

		assert_equal view.call, %(<article id="&quot;><script type=&quot;text/javascript&quot; src=&quot;bad_script.js&quot;></script>"></article>)
	end

	test "naughty javascript link protocol in symbolic href" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a href: "javascript:javascript:alert(1)" do
					"naughty link"
				end
			end
		end

		assert_equal view.call, %{<a>naughty link</a>}
	end

	test "naughty javascript link protocol in string href" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a "href" => "javascript:javascript:alert(1)" do
					"naughty link"
				end
			end
		end

		assert_equal view.call, %{<a>naughty link</a>}
	end

	test "naughty javascript link protocol with a hidden tab character" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a(href: "\tjavascript:alert(1)") { "XSS" }
				a(href: "j\tavascript:alert(1)") { "XSS" }
				a(href: "ja\tvascript:alert(1)") { "XSS" }
				a(href: "jav\tascript:alert(1)") { "XSS" }
				a(href: "java\tscript:alert(1)") { "XSS" }
				a(href: "javas\tcript:alert(1)") { "XSS" }
				a(href: "javasc\tript:alert(1)") { "XSS" }
				a(href: "javascr\tipt:alert(1)") { "XSS" }
				a(href: "javascri\tpt:alert(1)") { "XSS" }
				a(href: "javascrip\tt:alert(1)") { "XSS" }
				a(href: "javascript\t:alert(1)") { "XSS" }
				a(href: "javascript:\talert(1)") { "XSS" }
			end
		end

		output = view.call
		assert_equal output.scan("<a>").size, 12
		assert_equal output.scan("href").size, 0
	end

	test "naughty javascript link protocol with a hidden newline character" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a(href: "\njavascript:alert(1)") { "XSS" }
				a(href: "j\navascript:alert(1)") { "XSS" }
				a(href: "ja\nvascript:alert(1)") { "XSS" }
				a(href: "jav\nascript:alert(1)") { "XSS" }
				a(href: "java\nscript:alert(1)") { "XSS" }
				a(href: "javas\ncript:alert(1)") { "XSS" }
				a(href: "javasc\nript:alert(1)") { "XSS" }
				a(href: "javascr\nipt:alert(1)") { "XSS" }
				a(href: "javascri\npt:alert(1)") { "XSS" }
				a(href: "javascrip\nt:alert(1)") { "XSS" }
				a(href: "javascript\n:alert(1)") { "XSS" }
				a(href: "javascript:\nalert(1)") { "XSS" }
			end
		end

		output = view.call
		assert_equal output.scan("<a>").size, 12
		assert_equal output.scan("href").size, 0
	end

	test "naughty javascript link protocol with a hidden whitespace character" do
		view = Class.new(Phlex::HTML) do
			def view_template
				a(href: " javascript:alert(1)") { "XSS" }
				a(href: "j avascript:alert(1)") { "XSS" }
				a(href: "ja vascript:alert(1)") { "XSS" }
				a(href: "jav ascript:alert(1)") { "XSS" }
				a(href: "java script:alert(1)") { "XSS" }
				a(href: "javas cript:alert(1)") { "XSS" }
				a(href: "javasc ript:alert(1)") { "XSS" }
				a(href: "javascr ipt:alert(1)") { "XSS" }
				a(href: "javascri pt:alert(1)") { "XSS" }
				a(href: "javascrip t:alert(1)") { "XSS" }
				a(href: "javascript :alert(1)") { "XSS" }
				a(href: "javascript: alert(1)") { "XSS" }
			end
		end

		output = view.call
		assert_equal output.scan("<a>").size, 12
		assert_equal output.scan("href").size, 0
	end

	Phlex::SGML::Attributes::UNSAFE_ATTRIBUTES.each do |event_attribute|
		test "with naughty #{event_attribute} attribute" do
			naughty_attributes = { event_attribute => "alert(1);" }

			view = Class.new(Phlex::HTML) do
				define_method :view_template do
					__send__(:div, **naughty_attributes)
				end
			end

			error = assert_raises(ArgumentError) { view.call }
			assert_equal error.message, "Unsafe attribute name detected: #{event_attribute}."
		end
	end

	%w[< > & " '].each do |naughty_character|
		test "naughty attribute name containing #{naughty_character}" do
			naughty_attribute = "abc#{naughty_character}123"
			naughty_attributes = { naughty_attribute => "alert(1);" }

			view = Class.new(Phlex::HTML) do
				define_method :view_template do
					__send__(:div, **naughty_attributes)
				end
			end

			error = assert_raises(ArgumentError) { view.call }
			assert_equal error.message, "Unsafe attribute name detected: #{naughty_attribute}."
		end
	end
end
