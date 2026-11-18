# frozen_string_literal: true

class Phlex::SGML::SafeValue
	include Phlex::SGML::SafeObject

	def initialize(to_s)
		@to_s = to_s
	end

	attr_reader :to_s

	def ==(other)
		self.class == other.class && @to_s == other.to_s
	end

	def eql?(other)
		self.class == other.class && @to_s.eql?(other.to_s)
	end

	def hash
		[self.class, @to_s].hash
	end
end
