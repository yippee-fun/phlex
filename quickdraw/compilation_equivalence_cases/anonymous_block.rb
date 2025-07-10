class AnonymousBlock < Phlex::HTML
	def view_template(&)
		# Test forwarding anonymous block arguments
		wrapper(&)
		
		div do
			# Can't use & here since we're in a different block
			yield_content { "content" }
		end
		
		# Also test with explicit block
		outer(&)
		
		# Test with arguments and anonymous block
		render_with_args("hello", &)
		render_with_kwargs(class: "test", &)
		render_with_both("world", id: "foo", &)
	end
	
	def wrapper(&)
		div(class: "wrapper", &)
	end
	
	def yield_content
		span { "Before" }
		yield
		span { "After" }
	end
	
	def outer(&)
		div(class: "outer", &)
	end
	
	def render_with_args(text, &)
		div { text }
		yield if block_given?
	end
	
	def render_with_kwargs(**, &)
		div(**) { yield if block_given? }
	end
	
	def render_with_both(text, **, &)
		div(**) { text }
		yield if block_given?
	end
end