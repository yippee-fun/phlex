# frozen_string_literal: true

class Phlex::CSV
	FORMULA_PREFIXES_MAP = Array.new(128).tap do |map|
		"=+-@\t\r".each_byte do |byte|
			map[byte] = true
		end
	end.freeze

	UNDEFINED = Object.new

	def initialize(collection)
		@collection = collection
		@_row_buffer = []
		@_headers = []
		@_row_appender = nil
	end

	attr_reader :collection

	def call(buffer = +"", context: nil, delimiter: self.delimiter)
		ensure_escape_csv_injection_configured!

		strip_whitespace = trim_whitespace?
		escape_csv_injection = escape_csv_injection?
		row_buffer = @_row_buffer
		headers = @_headers
		has_yielder = respond_to?(:yielder, true)
		first_row = true
		render_headers = render_headers?

		if delimiter.length != 1
			raise Phlex::ArgumentError.new("Delimiter must be a single character")
		end

		if strip_whitespace
			escape_regex = /[\r\n"#{Regexp.escape(delimiter)}]/
		else
			escape_regex = /^\s|\s$|[\r\n"#{Regexp.escape(delimiter)}]/
		end

		if has_yielder
			warn <<~MESSAGE
				Custom yielders are deprecated in Phlex::CSV.

				Please replace your yielder with an `around_row` method.

				You should be able to just rename your yielder method
				and change `yield` to `super`.
			MESSAGE
		end

		row_appender = -> {
			row = row_buffer

			if first_row
				first_row = false

				i = 0
				number_of_columns = row.length
				first_col = true

				while i < number_of_columns
					header, = row[i]
					headers[i] = header

					if render_headers
						if first_col
							first_col = false
						else
							buffer << delimiter
						end

						__escape__(buffer, header, escape_csv_injection:, strip_whitespace:, escape_regex:)
					end
					i += 1
				end

				buffer << "\n" if render_headers
			end

			i = 0
			number_of_columns = row.length
			first_col = true

			while i < number_of_columns
				header, value = row[i]

				unless headers[i] == header
					raise Phlex::RuntimeError.new("Header mismatch at index #{i}: expected #{headers[i]}, got #{header}.")
				end

				if first_col
					first_col = false
				else
					buffer << delimiter
				end

				__escape__(buffer, value, escape_csv_injection:, strip_whitespace:, escape_regex:)
				i += 1
			end

			buffer << "\n"

			row_buffer.clear
		}

		if has_yielder
			each_item do |record|
				yielder(record) do |*a, **k|
					row_template(*a, **k)
					row_appender.call
				end
			end
		else
			@row_appender = row_appender
			each_item do |record|
				around_row(record)
			end
		end

		buffer
	end

	def around_row(...)
		row_template(...)
		@row_appender.call
	end

	def filename
		nil
	end

	def content_type
		"text/csv"
	end

	def delimiter
		","
	end

	private def column(header = nil, value)
		@_row_buffer << [header, value]
	end

	private def each_item(&)
		collection.each(&)
	end

	# Override and set to `false` to disable rendering headers.
	private def render_headers?
		true
	end

	# Override and set to `true` to strip leading and trailing whitespace from values.
	private def trim_whitespace?
		false
	end

	# Override and set to `false` to disable CSV injection escapes or `true` to enable.
	private def escape_csv_injection?
		UNDEFINED
	end

	private def __escape__(buffer, value, escape_csv_injection:, strip_whitespace:, escape_regex:)
		value = case value
		when String
			value
		when Symbol
			value.name
		else
			value.to_s
		end

		if strip_whitespace
			value = value.strip

			if escape_csv_injection
				if value.empty?
					buffer << value
				elsif FORMULA_PREFIXES_MAP[value.getbyte(0)]
					value.gsub!('"', '""')
					buffer << '"\'' << value << '"'
				elsif value.match?(escape_regex)
					value.gsub!('"', '""')
					buffer << '"' << value << '"'
				else
					buffer << value
				end
			else # not escaping CSV injection
				if value.match?(escape_regex)
					buffer << '"' << value.gsub('"', '""') << '"'
				else
					buffer << value
				end
			end
		else # not stripping whitespace
			if escape_csv_injection
				first_byte = value.getbyte(0)

				if value.empty?
					buffer << '""'
				elsif FORMULA_PREFIXES_MAP[first_byte]
					buffer << '"\'' << value.gsub('"', '""') << '"'
				elsif value.match?(escape_regex)
					buffer << '"' << value.gsub('"', '""') << '"'
				else
					buffer << value
				end
			else # not escaping CSV injection
				if value.empty?
					buffer << '""'
				elsif value.match?(escape_regex)
					buffer << '"' << value.gsub('"', '""') << '"'
				else
					buffer << value
				end
			end
		end
	end

	# Handle legacy `view_template` method
	private def respond_to_missing?(method_name, include_private)
		(method_name == :row_template && respond_to?(:view_template)) || super
	end

	# Handle legacy `view_template` method
	private def method_missing(method_name, ...)
		if method_name == :row_template && respond_to?(:view_template)
			warn "Deprecated: Use `row_template` instead of `view_template` in Phlex CSVs."
			self.class.alias_method :row_template, :view_template
			view_template(...)
		else
			super
		end
	end

	private def ensure_escape_csv_injection_configured!
		if escape_csv_injection? == UNDEFINED
			raise <<~MESSAGE
				You need to define `escape_csv_injection?` in #{self.class.name}.

				CSV injection is a security vulnerability where malicious spreadsheet
				formulae are used to execute code or exfiltrate data when a CSV is opened
				in a spreadsheet program such as Microsoft Excel or Google Sheets.

				For more information, see https://owasp.org/www-community/attacks/CSV_Injection

				If you’re sure this CSV will never be opened in a spreadsheet program,
				you can *disable* CSV injection escapes:

				  def escape_csv_injection? = false

				This is useful when using CSVs for byte-for-byte data exchange between secure systems.

				Alternatively, you can *enable* CSV injection escapes at the cost of data integrity:

				  def escape_csv_injection? = true

				Enabling the CSV injection escapes will prefix with a single quote `'` any
				values that start with: `=`, `+`, `-`, `@`, `\\t`, `\\r`

				Unfortunately, there is no one-size-fits-all solution to CSV injection.

				You need to decide based on your specific use case.
			MESSAGE
		end
	end
end
