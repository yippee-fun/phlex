# frozen_string_literal: true

module EquivalenceCases
	module RefinedClassMethod
		module NoSrcset
			refine(Phlex::SGML::Elements.singleton_class) { def normalize_img_attributes(attributes) = attributes.except(:srcset) }
		end
	end
end

using EquivalenceCases::RefinedClassMethod::NoSrcset

module EquivalenceCases
	module RefinedClassMethod
		class RefinedClassMethod < Phlex::HTML
			def view_template
				attributes = { src: "/a.png", srcset: ["a.png 1x", "b.png 2x"] }
				img(**attributes)
			end
		end
	end
end
