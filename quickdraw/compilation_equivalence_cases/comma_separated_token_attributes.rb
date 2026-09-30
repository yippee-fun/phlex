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
	end
end
