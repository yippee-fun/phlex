# frozen_string_literal: true

module Example
	class DynamicList < Phlex::HTML
		Record = Struct.new(:title, :summary)
		RECORDS = Array.new(100) { |i| Record.new("Title #{i}", "Summary <#{i}>").freeze }.freeze

		def view_template
			ul do
				RECORDS.each do |record|
					li do
						h2 { record.title }
						p { record.summary }
					end
				end
			end
		end
	end
end
