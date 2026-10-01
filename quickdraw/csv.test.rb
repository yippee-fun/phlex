# frozen_string_literal: true

class CSVTest < Quickdraw::Test
	Product = Struct.new(:name, :price)

	class Base < Phlex::CSV
		def row_template(product)
			column("name", product.name)
			column("price", product.price)
		end
	end

	products = [
		Product.new("Apple", 1.00),
		Product.new(" Banana ", 2.00),
		Product.new(:strawberry, "Three pounds"),
		Product.new("=SUM(A1:B1)", "=SUM(A1:B1)"),
		Product.new("Abc, \"def\"", "Foo\nbar \"baz\""),
		Product.new("", ""),
		Product.new(nil, nil),
	]

	test "don’t escape csv injection or trim whitespace" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { false }
			define_method(:trim_whitespace?) { false }
		end

		assert_equal example.new(products).call, <<~CSV
   name,price
   Apple,1.0
   " Banana ",2.0
   strawberry,Three pounds
   =SUM(A1:B1),=SUM(A1:B1)
   "Abc, ""def""","Foo\nbar ""baz"""
   "",""
   "",""
CSV
	end

	test "don’t escape csv injection, but do trim whitespace" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { false }
			define_method(:trim_whitespace?) { true }
		end

		assert_equal example.new(products).call, <<~CSV
   name,price
   Apple,1.0
   Banana,2.0
   strawberry,Three pounds
   =SUM(A1:B1),=SUM(A1:B1)
   "Abc, ""def""","Foo\nbar ""baz"""
   ,
   ,
CSV
	end

	test "trimming without formula protection still quotes CSV syntax" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = false
			def trim_whitespace? = true

			def row_template(value)
				column "value", value
			end
		end

		output = example.new([" a,b ", ' a"b ', " a\nb "]).call
		assert_equal output, "value\n\"a,b\"\n\"a\"\"b\"\n\"a\nb\"\n"
	end

	test "escape csv injection, but don’t trim whitespace" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { true }
			define_method(:trim_whitespace?) { false }
		end

		assert_equal example.new(products).call, <<~CSV
   name,price
   Apple,1.0
   " Banana ",2.0
   strawberry,Three pounds
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "Abc, ""def""","Foo
   bar ""baz"""
   "",""
   "",""
CSV
	end

	test "escape csv injection and trim whitespace" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { true }
			define_method(:trim_whitespace?) { true }
		end

		assert_equal example.new(products).call, <<~CSV
   name,price
   Apple,1.0
   Banana,2.0
   strawberry,Three pounds
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "Abc, ""def""","Foo
   bar ""baz"""
   ,
   ,
CSV
	end

	test "internal carriage returns are quoted with every escape configuration" do
		[true, false].each do |trim|
			[true, false].each do |protect|
				example = Class.new(Phlex::CSV) do
					define_method(:escape_csv_injection?) { protect }
					define_method(:trim_whitespace?) { trim }
					def row_template(value)
						column "head\rer", value
					end
				end

				assert_equal example.new(["a\rb", "a\r\nb"]).call,
					"\"head\rer\"\n\"a\rb\"\n\"a\r\nb\"\n"
			end
		end
	end

	test "no headers" do
		example = Class.new(Base) do
			define_method(:render_headers?) { false }
			define_method(:escape_csv_injection?) { false }
		end

		assert_equal example.new(products).call, <<~CSV
   Apple,1.0
   " Banana ",2.0
   strawberry,Three pounds
   =SUM(A1:B1),=SUM(A1:B1)
   "Abc, ""def""","Foo
   bar ""baz"""
   "",""
   "",""
CSV
	end

	test "rejects rows with a different number of columns before writing them" do
		[true, false].each do |render_headers|
			[true, false].each do |named_headers|
				example = Class.new(Phlex::CSV) do
					def escape_csv_injection? = false
					define_method(:render_headers?) { render_headers }

					define_method(:row_template) do |row|
						row.each_with_index do |value, index|
							column(named_headers ? "H#{index}" : nil, value)
						end
					end
				end

				[[], ["c"], ["c", "d", "e"]].each do |row|
					buffer = +""
					error = assert_raises(Phlex::RuntimeError) do
						example.new([["a", "b"], row]).call(buffer)
					end

					assert_equal error.message, "Column count mismatch: expected 2, got #{row.length}."
					assert_equal buffer, example.new([["a", "b"]]).call
				end
			end
		end
	end

	test "checks column counts when the first row is empty" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = false

			def row_template(row)
				row.each { |value| column(value) }
			end
		end

		assert_equal example.new([[], []]).call, "\n\n\n"

		error = assert_raises(Phlex::RuntimeError) do
			example.new([[], ["a"]]).call
		end

		assert_equal error.message, "Column count mismatch: expected 0, got 1."
	end

	test "clears the rejected row so rendering can continue" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = false

			def row_template(row)
				row.each { |value| column(value) }
			end

			def around_row(row)
				super
			rescue Phlex::RuntimeError
				nil
			end
		end

		assert_equal example.new([["a", "b"], ["c"], ["d", "e"]]).call, <<~CSV
			"",""
			a,b
			d,e
		CSV
	end

	test "does not write a row with a header mismatch" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = false

			def row_template(row)
				column("A", row[0])
				column(row[1], row[2])
			end

			def around_row(row)
				super
			rescue Phlex::RuntimeError
				nil
			end
		end

		assert_equal example.new([[1, "B", 2], [3, "C", 4], [5, "B", 6]]).call, <<~CSV
			A,B
			1,2
			5,6
		CSV
	end

	test "with a custom around_row" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = true

			def around_row(item)
				super(item.name, item.price)
			end

			def row_template(name, price)
				column "Name", name
				column "Price", price
			end
		end

		assert_equal example.new(products).call, <<~CSV
   Name,Price
   Apple,1.0
   " Banana ",2.0
   strawberry,Three pounds
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "Abc, ""def""","Foo
   bar ""baz"""
   "",""
   "",""
CSV
	end

	test "with an around_row that calls super more than once" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = true
			def trim_whitespace? = false

			def around_row(item)
				super(item.name, item.price)
				super(item.name, item.price)
			end

			def row_template(name, price)
				column "Name", name
				column "Price", price
			end
		end

		assert_equal example.new(products).call, <<~CSV
   Name,Price
   Apple,1.0
   Apple,1.0
   " Banana ",2.0
   " Banana ",2.0
   strawberry,Three pounds
   strawberry,Three pounds
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "Abc, ""def""","Foo\nbar ""baz"""
   "Abc, ""def""","Foo\nbar ""baz"""
   "",""
   "",""
   "",""
   "",""
CSV
	end

	test "with a yielder that yields more than once" do
		example = Class.new(Phlex::CSV) do
			def escape_csv_injection? = true
			def trim_whitespace? = false

			def yielder(item)
				yield(item.name, item.price)
				yield(item.name, item.price)
			end

			def row_template(name, price)
				column "Name", name
				column "Price", price
			end
		end

		assert_equal example.new(products).call, <<~CSV
   Name,Price
   Apple,1.0
   Apple,1.0
   " Banana ",2.0
   " Banana ",2.0
   strawberry,Three pounds
   strawberry,Three pounds
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "'=SUM(A1:B1)","'=SUM(A1:B1)"
   "Abc, ""def""","Foo\nbar ""baz"""
   "Abc, ""def""","Foo\nbar ""baz"""
   "",""
   "",""
   "",""
   "",""
CSV
	end

	test "with a custom delimiter defined as a method" do
		example = Class.new(Phlex::CSV) do
			define_method(:escape_csv_injection?) { true }
			define_method(:trim_whitespace?) { true }
			define_method(:delimiter) { ";" }
			define_method(:row_template) do |product|
				column "Name", product.name
				column "Price", product.price
			end
		end

		assert_equal example.new(products).call, <<~CSV
   Name;Price
   Apple;1.0
   Banana;2.0
   strawberry;Three pounds
   "'=SUM(A1:B1)";"'=SUM(A1:B1)"
   "Abc, ""def""";"Foo
   bar ""baz"""
   ;
   ;
CSV
	end

	test "with a custom delimiter passed in as an argument" do
		example = Class.new(Phlex::CSV) do
			define_method(:escape_csv_injection?) { true }
			define_method(:trim_whitespace?) { true }
			define_method(:row_template) do |product|
				column "Name", product.name
				column "Price", product.price
			end
		end

		assert_equal example.new(products).call(delimiter: ";"), <<~CSV
   Name;Price
   Apple;1.0
   Banana;2.0
   strawberry;Three pounds
   "'=SUM(A1:B1)";"'=SUM(A1:B1)"
   "Abc, ""def""";"Foo
   bar ""baz"""
   ;
   ;
CSV
	end

	["]", "\\", "[", "-", "^"].each do |delimiter|
		test "quotes headers and values containing the #{delimiter.inspect} delimiter" do
			[true, false].each do |trim|
				[true, false].each do |protect|
					example = Class.new(Phlex::CSV) do
						define_method(:escape_csv_injection?) { protect }
						define_method(:trim_whitespace?) { trim }
						define_method(:row_template) do |value|
							column "head#{delimiter}er", value
							column "other", "plain"
						end
					end

					assert_equal example.new(["a#{delimiter}b"]).call(delimiter:),
						"\"head#{delimiter}er\"#{delimiter}other\n\"a#{delimiter}b\"#{delimiter}plain\n"
				end
			end
		end
	end

	test "with an invalid custom delimiter" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { true }
		end

		error = assert_raises(Phlex::ArgumentError) do
			example.new([]).call(delimiter: "invalid")
		end

		assert_equal error.message, "Delimiter must be a single character"
	end

	test "content type" do
		assert_equal Base.new([]).content_type, "text/csv"
	end

	test "filename is nil by default" do
		assert_equal Base.new([]).filename, nil
	end

	test "raises an error if there's no escape plan" do
		error = assert_raises(RuntimeError) do
			Base.new([]).call
		end

		assert_includes error.message, "escape_csv_injection?"
	end
end
