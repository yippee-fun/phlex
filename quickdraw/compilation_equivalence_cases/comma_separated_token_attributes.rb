# frozen_string_literal: true

module EquivalenceCases
	module CommaSeparatedTokenAttributes
		class Static < Phlex::HTML
			def view_template
				img(srcset: ["a.jpg 1x", "b.jpg 2x"], src: "a.jpg")
				link(rel: "preload", as: "image", imagesrcset: ["a.jpg 1x", "b.jpg 2x"])
				link(rel: "stylesheet", media: ["screen", "print"])
				input(type: "file", accept: ["image/png", "image/jpeg"])
			end
		end

		class Dynamic < Phlex::HTML
			def view_template
				srcs = ["a.jpg 1x", "b.jpg 2x"]
				img(srcset: srcs, src: "a.jpg")
				input(type: "file", accept: srcs)
			end
		end

		class DynamicTags < Phlex::HTML
			def view_template
				div do
					tag(:img, srcset: ["a.jpg 1x", ["b,c.jpg 2x"]])
					tag(:link, rel: "preload", as: "image", imagesrcset: ["a.jpg 1x", "b.jpg 2x"])
					tag(:link, media: ["screen", "print"], sizes: ["16x16", "32x32"])
					tag(:input, type: "file", accept: ["image/png", "image/jpeg"])
				end
			end
		end
	end
end
