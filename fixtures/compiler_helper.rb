# frozen_string_literal: true

module CompilerHelper
	# Restores the compiler as it was, so a suite run with it enabled stays enabled.
	def with_lazy_compilation(**)
		enabled = Phlex::Compiler.enabled?
		on_failure = Phlex::Compiler.instance_variable_get(:@on_failure)
		Phlex::Compiler.enable!(**)
		yield
	ensure
		enabled ? Phlex::Compiler.enable!(on_failure:) : Phlex::Compiler.disable!
	end
end
