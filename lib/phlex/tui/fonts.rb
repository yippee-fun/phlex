# frozen_string_literal: true

module Phlex::TUI::Fonts
	def self.script(text)
		text.gsub(/[A-Za-z]/, Script)
	end

	def self.bold_script(text)
		text.gsub(/[A-Za-z]/, BoldScript)
	end

	def self.circled(text)
		text.gsub(/[A-Za-z]/, Circled)
	end

	def self.negative_circled(text)
		text.upcase.gsub(/[A-Z0-9]/, NegativeCircled)
	end

	# ⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄⠄⠂⠁⠁⠂⠄
end
