# frozen_string_literal: true

class TUIFrameDifferTest < Quickdraw::Test
	test "returns empty output when there are no row changes" do
		differ = Phlex::TUI::FrameDiffer.new

		assert_equal differ.diff(["abc", "def"], ["abc", "def"]), ""
	end

	test "rewrites only changed rows" do
		differ = Phlex::TUI::FrameDiffer.new

		assert_equal differ.diff(["abc", "def"], ["abc", "xyz"]), "\e[2;1Hxyz"
	end

	test "full output homes and clears before writing rows" do
		differ = Phlex::TUI::FrameDiffer.new

		assert_equal differ.full(["one", "two"], clear: true), "\e[H\e[2Jone\ntwo"
	end
end
