# frozen_string_literal: true

require "json"

# Every file in compilation_equivalence_cases defines one or more Phlex::SGML
# subclasses. Each class is rendered in several ways before and after its file
# is compiled, and every observation must be identical.
#
# A class can add its own renders by defining
# `def self.equivalence_scenarios = { "name" => ->(klass) { ... } }`.
class CompilationEquivalenceTest < Quickdraw::Test
	CASES_DIR = File.expand_path("compilation_equivalence_cases", __dir__)

	# Cases that can't pass until an upstream fix lands, with the reason.
	PENDING = {}.freeze

	# Cases whose every method is expected to be left alone by the compiler.
	NOTHING_TO_COMPILE = %w[positional_arguments].freeze

	# Cases the compiler is expected to refuse, with the reason it must give.
	REFUSED = {
		"same_line_definitions" => /more than one method is defined on this line/,
		"reserved_locals" => /__phlex_done_1__ is a local the compiler reserves/,
		"refinement_mid_file" => /`using` applies to only part of the file/,
		"ruby2_keywords" => /marked ruby2_keywords/,
		"ruby2_keywords_reopened" => /marked ruby2_keywords/,
		"ruby2_keywords_alias" => /delegate is marked ruby2_keywords/,
		"conditional_using" => /isn.t a plain top-level statement naming a constant/,
		"ruby2_keywords_splat" => /arguments the compiler can.t read/,
	}.freeze

	DEFAULT_SCENARIOS = {
		"call" => -> (klass) { klass.new.call },
		"call again" => -> (klass) { klass.new.call },
		"streaming chunks" => -> (klass) { [].tap { |chunks| klass.new.call(chunks) } },
	}.freeze

	Dir["#{CASES_DIR}/*.rb"].each do |file|
		name = File.basename(file, ".rb")

		test name do
			require file

			components = components_defined_in(file)
			assert(components.any?) { "#{name} defines no Phlex::SGML subclasses" }

			problems = REFUSED.key?(name) ? expect_refusal(file, REFUSED[name]) : compile_and_compare(components, file)

			if !NOTHING_TO_COMPILE.include?(name) && !REFUSED.key?(name) && Phlex::Compiler::MAP.values.none? { |generation| generation.path == file }
				problems << "nothing in #{name} was compiled, so the case doesn't exercise the compiler"
			end

			if PENDING.key?(name)
				refute(problems.empty?) { "#{name} passes now, so remove it from PENDING (#{PENDING[name]})" }
			else
				assert(problems.empty?) { problems.join("\n\n") }
			end
		end
	end

	require_relative "../fixtures/page"
	require_relative "../fixtures/layout"
	require_relative "../fixtures/dynamic_list"

	test "dynamic list fixture" do
		before = Example::DynamicList.new.call
		Phlex::Compiler.compile(Example::DynamicList)
		after = Example::DynamicList.new.call

		assert_equal after, before
	end

	test "benchmark fixtures" do
		before = Example::Page.new.call
		Phlex::Compiler.compile(Example::LayoutComponent)
		Phlex::Compiler.compile(Example::Page)
		after = Example::Page.new.call

		assert_equal after, before
	end

	private def expect_refusal(file, reason)
		Phlex::Compiler.compile_file(file)
		["compilation was expected to be refused with #{reason.inspect} but succeeded"]
	rescue Phlex::Compiler::Error => e
		e.message.match?(reason) ? [] : ["compilation was refused for a different reason: #{e.message}"]
	end

	# Returns a description of every observation that changed, or of the compile error.
	private def compile_and_compare(components, file)
		before = observe(components, file)

		begin
			Phlex::Compiler.compile_file(file)
		rescue Exception => e
			return ["compilation raised #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"]
		end

		after = observe(components, file)

		before.filter_map do |key, observation|
			next if after[key] == observation

			"#{key.join(' / ')} changed after compilation\n\nBefore:\n#{observation.inspect}\n\nAfter:\n#{after[key].inspect}"
		end
	end

	private def components_defined_in(file)
		ObjectSpace.each_object(Class).select do |klass|
			klass < Phlex::SGML && klass.name && constant_source_path(klass.name) == file
		end.sort_by(&:name)
	end

	# Other tests may have removed a constant that its class still names.
	private def constant_source_path(name)
		Object.const_source_location(name)&.first
	rescue NameError
		nil
	end

	private def observe(components, file)
		components.each_with_object({}) do |klass, observations|
			scenarios = DEFAULT_SCENARIOS.dup
			scenarios.merge!(klass.equivalence_scenarios) if klass.respond_to?(:equivalence_scenarios)

			scenarios.each do |scenario_name, scenario|
				observations[[klass.name, scenario_name]] = observe_scenario(scenario, klass, file)
			end

			observations[[klass.name, "private methods"]] = klass.private_instance_methods(false).sort
			observations[[klass.name, "public methods"]] = klass.public_instance_methods(false).sort
		end
	end

	private def observe_scenario(scenario, klass, file)
		[:ok, scenario.call(klass)]
	rescue Exception => e
		[:raised, e.class, e.message, first_line_in(e, file)]
	end

	# The line in the case file that raised, from either a native or a source-mapped backtrace.
	private def first_line_in(exception, file)
		exception.backtrace.each do |frame|
			return Regexp.last_match(1).to_i if frame =~ /#{Regexp.escape(file)}:(\d+)/
		end

		nil
	end
end
