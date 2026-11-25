# frozen_string_literal: true

module CompilerHelper
	# Restores the compiler as it was, so a suite run with it enabled stays
	# enabled. The suite's failure handler is kept unless the test passes one.
	def with_lazy_compilation(on_failure: Phlex::Compiler.instance_variable_get(:@on_failure))
		enabled = Phlex::Compiler.enabled?
		previous = Phlex::Compiler.instance_variable_get(:@on_failure)
		Phlex::Compiler.enable!(on_failure:)
		yield
	ensure
		enabled ? Phlex::Compiler.enable!(on_failure: previous) : Phlex::Compiler.disable!
	end

	def without_lazy_compilation
		enabled = Phlex::Compiler.enabled?
		Phlex::Compiler.disable!
		yield
	ensure
		Phlex::Compiler.enable!(on_failure: Phlex::Compiler.instance_variable_get(:@on_failure)) if enabled
	end
end
