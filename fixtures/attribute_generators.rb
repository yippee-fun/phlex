# frozen_string_literal: true

# Quickdraw generators for attribute hashes, with words that reach the
# escaping, reference and unsafe-name checks.
module AttributeGenerators
	G = Quickdraw::Generators

	TEXT_WORDS = (
		%w[javascript: JavaScript java script : &colon; &Colon; &#58; &#x3a; &#X3A &#106; &#x6A; &#0000106 &#xD800;] +
		%w[&tab; &Tab; &newline; &NewLine; &#9; &#x0a; &amp; &quot; & # ; " ' < > / = _ - j J] +
		" \t\n\r\0\fİKſ".chars
	).freeze

	NAME_WORDS = (
		%w[on ON click href Href src xlink xlink:href formaction srcdoc sandbox http-equiv http equiv] +
		%w[id ID data aria style class title _ - : " ' = < > /] +
		" \t\0İK".chars
	).freeze

	TEXT = G.one_of(G.string(:ascii, dictionary: TEXT_WORDS), G.string(dictionary: TEXT_WORDS))
	NAME = G.string(:ascii, length: 0..10, dictionary: NAME_WORDS)
	KEY = G.one_of(NAME.map(&:to_sym), NAME, :_)

	SCALAR = G.one_of(
		TEXT,
		NAME.map(&:to_sym),
		G.integer,
		G.float,
		true,
		false,
		nil,
		TEXT.map { |text| Phlex::SGML::SafeValue.new(text) },
	)

	TOKENS = G.array(G.one_of(SCALAR, G.array(SCALAR, length: 0..3)), length: 0..4)

	NESTED = G.hash_of(KEY, G.one_of(SCALAR, TOKENS, G.hash_of(KEY, SCALAR, length: 0..3)), length: 0..3)

	VALUE = G.one_of(SCALAR, TOKENS, TOKENS.map { |tokens| Set.new(tokens) }, NESTED)

	ATTRIBUTES = G.hash_of(KEY, VALUE, length: 0..4)

	# Text that isn't valid UTF-8 or isn't ASCII-compatible, which some string
	# operations refuse.
	ENCODED_TEXT = G.one_of(
		TEXT.map { |text| text.encode(Encoding::UTF_16LE) },
		TEXT.map { |text| (text.b << "\xFF".b).force_encoding(Encoding::UTF_8) },
		TEXT.map { |text| text.b << "\xFF".b },
	)
end
