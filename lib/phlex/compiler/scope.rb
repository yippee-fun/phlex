# frozen_string_literal: true

# Loaded afresh for each file the compiler evaluates, to give it a top-level
# scope of its own, so a `using` in one compiled file doesn't reach the next
# any more than it would between real files. Not autoloaded.
Phlex::Compiler::SCOPES << binding
