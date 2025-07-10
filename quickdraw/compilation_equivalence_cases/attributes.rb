# frozen_string_literal: true

class Attributes < Phlex::HTML
	def view_template
		div(
			a: nil,
			b: 1,
			c: :two,
			d: "three",
			e: 4.5,
			f: false,
			g: true,
			h: [nil, 1, :two, "three", 4.5, [1]],
			i: Set[nil, 1, :two, "three", 4.5, [1]],
			j: {
				k: 1,
				"l" => 2
			},
			"m" => 3
		)
	end
end
