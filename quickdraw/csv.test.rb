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

	test "values containing the delimiter are quoted when trimming whitespace without escaping csv injection" do
		example = Class.new(Base) do
			define_method(:escape_csv_injection?) { false }
			define_method(:trim_whitespace?) { true }
		end

		assert_equal example.new([Product.new(" x,y ", "1")]).call, %(name,price\n"x,y",1\n)
	end

	test "values containing a carriage return are quoted" do
		[true, false].each do |trim_whitespace|
			example = Class.new(Base) do
				define_method(:escape_csv_injection?) { false }
				define_method(:trim_whitespace?) { trim_whitespace }
			end

			assert_equal example.new([Product.new("a\rb", "1")]).call, %(name,price\n"a\rb",1\n)
		end
	end

	test "a CSV can be rendered again after a wider one" do
		example = Class.new(Phlex::CSV) do
			define_method(:escape_csv_injection?) { false }
			define_method(:row_template) do |row|
				row.each { |value| column value }
			end
		end

		csv = example.new([["a", "b"]])
		assert_equal csv.call, %("",""\na,b\n)

		csv.collection.replace([["c"]])
		assert_equal csv.call, %(""\nc\n)
	end

	["[", "]", "\\", "^", "-", "|", "."].each do |delimiter|
		test "with #{delimiter.inspect} as the delimiter" do
			example = Class.new(Base) do
				define_method(:escape_csv_injection?) { false }
			end

			rows = [Product.new("a#{delimiter}b", "c"), Product.new("d", "e")]

			assert_equal example.new(rows).call(delimiter:), %(name#{delimiter}price\n"a#{delimiter}b"#{delimiter}c\nd#{delimiter}e\n)
		end
	end

	test "raises when a row has fewer columns than the first row" do
		example = Class.new(Phlex::CSV) do
			define_method(:escape_csv_injection?) { false }
			define_method(:row_template) do |product|
				column "name", product.name
				column "price", product.price if product.price
			end
		end

		error = assert_raises(Phlex::RuntimeError) do
			example.new([Product.new("Apple", 1), Product.new("Banana", nil)]).call
		end

		assert_equal error.message, "Column count mismatch: expected 2, got 1."
	end

	test "raises when a row has more columns than the first row" do
		example = Class.new(Phlex::CSV) do
			define_method(:escape_csv_injection?) { false }
			define_method(:render_headers?) { false }
			define_method(:row_template) do |product|
				column product.name
				column product.price if product.price
			end
		end

		error = assert_raises(Phlex::RuntimeError) do
			example.new([Product.new("Apple", nil), Product.new("Banana", 2)]).call
		end

		assert_equal error.message, "Column count mismatch: expected 1, got 2."
	end
end
