# frozen_string_literal: true

include Phlex::Helpers

test "nil + string" do
	output = mix({ class: nil }, { class: "a" })
	assert_equal output, { class: "a" }
end

test "string + nil" do
	output = mix({ class: "a" }, { class: nil })
	assert_equal output, { class: "a" }
end

test "array + nil" do
	output = mix({ class: ["foo", "bar"] }, { class: nil })
	assert_equal output, { class: ["foo", "bar"] }
end

test "array + array" do
	output = mix({ class: ["foo"] }, { class: ["bar"] })
	assert_equal output, { class: ["foo", "bar"] }
end

test "array + set" do
	output = mix({ class: ["foo"] }, { class: Set["bar"] })
	assert_equal output, { class: ["foo", "bar"] }
end

test "array + hash" do
	output = mix(
		{ data: ["foo"] },
		{ data: { controller: "bar" } },
	)

	assert_equal output, { data: { _: ["foo"], controller: "bar" } }
end

test "array + string" do
	output = mix({ class: ["foo"] }, { class: "bar" })
	assert_equal output, { class: ["foo", "bar"] }
end

test "hash + hash" do
	output = mix(
		{ data: { controller: "foo" } },
		{ data: { controller: "bar" } },
	)

	assert_equal output, { data: { controller: "foo bar" } }
end

test "string + array" do
	output = mix({ class: "foo" }, { class: ["bar"] })
	assert_equal output, { class: ["foo", "bar"] }
end

test "string + string" do
	output = mix({ class: "foo" }, { class: "bar" })
	assert_equal output, { class: "foo bar" }
end

test "string + set" do
	output = mix({ class: "foo" }, { class: Set["bar"] })
	assert_equal output, { class: ["foo", "bar"] }
end

test "override" do
	output = mix({ class: "foo" }, { class!: "bar" })
	assert_equal output, { class: "bar" }
end

test "set + set" do
	output = mix({ class: Set["foo"] }, { class: Set["bar"] })
	assert_equal output, { class: Set["foo", "bar"] }
end

test "set + array" do
	output = mix({ class: Set["foo"] }, { class: ["bar"] })
	assert_equal output, { class: ["foo", "bar"] }
end

test "set + string" do
	output = mix({ class: Set["foo"] }, { class: "bar" })
	assert_equal output, { class: ["foo", "bar"] }
end
