# frozen_string_literal: true

describe Phlex::HTML do
	extend ViewHelper

	with "naughty javascript links" do
		view do
			def template
				a(href: "javascript:alert(1)") { "a" }
				a(href: "JAVASCRIPT:alert(1)") { "b" }
				a(href: :"JAVASCRIPT:alert(1)") { "c" }
				a(HREF: "javascript:alert(1)") { "d" }
			end
		end

		it "removes the href attributes" do
			expect(output).to be == "<a>a</a><a>b</a><a>c</a><a>d</a>"
		end
	end

	with "naughty uppercase event tag" do
		view do
			def template
				button ONCLICK: "ALERT(1)" do
					"naughty button"
				end
			end
		end

		it "raises" do
			expect { output }.to raise_exception ArgumentError,
				message: be == "Unsafe attribute name detected: ONCLICK."
		end
	end

	with "naughty text" do
		view do
			def view_template
				plain %("><script type="text/javascript" src="bad_script.js"></script>)
			end
		end

		it "escapes the content" do
			expect(output).to be == "&quot;&gt;&lt;script type=&quot;text/javascript&quot; src=&quot;bad_script.js&quot;&gt;&lt;/script&gt;"
		end
	end

	with "naughty tag attribute values" do
		view do
			def view_template
				article id: %("><script type="text/javascript" src="bad_script.js"></script>)
			end
		end

		it "escapes the attributes" do
			expect(output).to be == %(<article id="&quot;&gt;&lt;script type=&quot;text/javascript&quot; src=&quot;bad_script.js&quot;&gt;&lt;/script&gt;"></article>)
		end
	end

	with "naughty javascript link protocol in href" do
		view do
			def view_template
				a href: "javascript:javascript:alert(1)" do
					"naughty link"
				end
			end
		end

		it "strips the javascript protocol" do
			expect(output).to be == %{<a>naughty link</a>}
		end
	end

	with "naughty javascript link protocol in href" do
		view do
			def view_template
				a "href" => "javascript:javascript:alert(1)" do
					"naughty link"
				end
			end
		end

		it "strips the javascript protocol" do
			expect(output).to be == %{<a>naughty link</a>}
		end
	end

	with "naughty javascript link protocol with a hidden tab character" do
		view do
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

		it "strips the javascript protocol" do
			expect(output.scan("<a>").size).to be == 12
			expect(output.scan("href").size).to be == 0
		end
	end

	with "naughty javascript link protocol with a hidden newline character" do
		view do
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

		it "strips the javascript protocol" do
			expect(output.scan("<a>").size).to be == 12
			expect(output.scan("href").size).to be == 0
		end
	end

	with "naughty javascript link protocol with a hidden whitespace character" do
		view do
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

		it "strips the javascript protocol" do
			expect(output.scan("<a>").size).to be == 12
			expect(output.scan("href").size).to be == 0
		end
	end

	with "naughty javascript link protocol with encoded characters" do
		view do
			def view_template
				a(href: "java&#x73;cript:alert(1)") { "XSS" }
				a(href: "javascript&#58;alert(1)") { "XSS" }
				a(href: "java&#115;cript:alert(1)") { "XSS" }
				a(href: "&#106;avascript:alert(1)") { "XSS" }
				a(href: "javascript&#58alert(1)") { "XSS" }
				a(href: "javascript&colon;alert(1)") { "XSS" }
			end
		end

		it "strips the javascript protocol" do
			expect(output.scan("<a>").size).to be == 6
			expect(output.scan("href").size).to be == 0
		end
	end

	with "naughty javascript link protocol in xlink:href" do
		view do
			def view_template
				svg do |s|
					s.a("xlink:href": "javascript:alert(1)") { "XSS" }
					s.a("xlink:href": "javascript&colon;alert(1)") { "XSS" }
					s.a("xlink:href": "javascript&#58alert(1)") { "XSS" }
				end
			end
		end

		it "strips the javascript protocol" do
			expect(output.scan("<a>").size).to be == 3
			expect(output.scan("xlink:href").size).to be == 0
		end
	end

	Phlex::HTML::EVENT_ATTRIBUTES.each_key do |event_attribute|
		with "with naughty #{event_attribute} attribute" do
			naughty_attributes = { event_attribute => "alert(1);" }

			view do
				define_method :view_template do
					send(:div, **naughty_attributes)
				end
			end

			it "raises an ArgumentError" do
				expect { output }.to raise_exception ArgumentError,
					message: be == "Unsafe attribute name detected: #{event_attribute}."
			end
		end
	end

	["<", ">", "&", "\"", "'", " ", "/", "="].each do |naughty_character|
		with "naughty attribute name containing #{naughty_character}" do
			naughty_attribute = "abc#{naughty_character}123"
			naughty_attributes = { naughty_attribute => "alert(1);" }

			view do
				define_method :view_template do
					send(:div, **naughty_attributes)
				end
			end

			it "raises an ArgumentError" do
				expect { output }.to raise_exception ArgumentError,
					message: be == "Unsafe attribute name detected: #{naughty_attribute}."
			end
		end
	end
end
