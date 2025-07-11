# frozen_string_literal: true

class HeredocInHash < Phlex::HTML
	def view_template
		# Test heredoc as hash value
		hash = i18n_zip_code_label
		div { plain hash[:x_text] }
	end

	def i18n_zip_code_label
		{ x_text: <<~JS }
			() => {
				switch(country) {
				case "US":
				case "AS":
				case "GU":
				case "MH":
				case "FM":
				case "MP":
				case "PW":
				case "PR":
				case "VI":
					return "Zip Code"
				case "CA":
					return "Postal Code"
				default:
					return "Postcode"
				}
			}
		JS
	end
end