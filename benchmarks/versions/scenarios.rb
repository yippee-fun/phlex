# frozen_string_literal: true

# Realistic pages for comparing Phlex versions. Written against the API that
# both 2.4 and 3.0 share, so the same file renders on either.

module Bench
	Order = Struct.new(:id, :number, :customer, :email, :total_cents, :status, :placed_on, :items)
	Post = Struct.new(:title, :slug, :author, :published_on, :sections, :tags)
	Section = Struct.new(:heading, :anchor, :paragraphs, :code)
	Comment = Struct.new(:id, :author, :avatar, :body, :posted_at, :likes)
	Product = Struct.new(:id, :name, :brand, :price_cents, :sale_cents, :rating, :reviews, :image, :colors, :in_stock)
	Field = Struct.new(:name, :label, :type, :value, :hint, :error, :required)

	STATUSES = %i[pending paid shipped refunded cancelled].freeze

	ORDERS = Array.new(50) do |i|
		Order.new(
			1000 + i,
			"ORD-#{(1000 + i).to_s.rjust(6, '0')}",
			"Customer #{i} & Sons",
			"customer#{i}@example.com",
			((i * 1733) % 50_000) + 999,
			STATUSES[i % STATUSES.length],
			"2026-11-#{((i % 28) + 1).to_s.rjust(2, '0')}",
			(i % 9) + 1,
		).freeze
	end.freeze

	PARAGRAPH = "Phlex lets you write views in Ruby. It escapes <script> tags & \"quotes\" for you, so user content is safe by default. Components compose like any other Ruby object."

	POST = Post.new(
		"Rendering HTML at the speed of thought",
		"rendering-html",
		"Jo Bloggs",
		"2026-11-25",
		Array.new(8) do |s|
			Section.new(
				"Section #{s + 1}: Why <views> matter",
				"section-#{s + 1}",
				Array.new(5) { |p| "#{PARAGRAPH} (#{s}.#{p})" }.freeze,
				(s.even? ? "class Hello < Phlex::HTML\n\tdef view_template\n\t\th1 { \"Hello <world>\" }\n\tend\nend" : nil),
			).freeze
		end.freeze,
		%w[ruby phlex performance views html].freeze,
	).freeze

	COMMENTS = Array.new(30) do |i|
		Comment.new(i, "Reader #{i}", "/avatars/#{i % 12}.png", "Great post! I tried this & it was <b>fast</b>. Comment number #{i}.", "2026-11-#{((i % 28) + 1).to_s.rjust(2, '0')}T12:00:00Z", i * 3 % 17).freeze
	end.freeze

	PRODUCTS = Array.new(60) do |i|
		Product.new(
			i,
			"Product #{i} \"Deluxe\"",
			%w[Acme Globex Initech Umbrella][i % 4],
			((i * 997) % 20_000) + 500,
			((i % 5 == 0) ? ((i * 997) % 15_000) + 400 : nil),
			(i % 5) + 1,
			i * 11 % 400,
			"/images/products/#{i}.webp",
			%w[red green blue black white].first((i % 5) + 1).freeze,
			i % 7 != 0,
		).freeze
	end.freeze

	COUNTRIES = Array.new(120) { |i| ["c#{i}", "Country #{i}"].freeze }.freeze

	FIELDS = Array.new(24) do |i|
		Field.new(
			"user[field_#{i}]",
			"Field #{i}",
			%w[text email password tel url number][i % 6],
			(i.odd? ? "value #{i} <&>" : nil),
			"Hint for field #{i}.",
			((i % 5 == 0) ? "can’t be blank" : nil),
			i % 3 == 0,
		).freeze
	end.freeze

	NAV = [["Dashboard", "/"], ["Orders", "/orders"], ["Products", "/products"], ["Customers", "/customers"], ["Reports", "/reports"], ["Settings", "/settings"]].freeze

	module UI
		extend Phlex::Kit

		class Layout < Phlex::HTML
			def initialize(title:, current:)
				@title = title
				@current = current
			end

			def view_template(&)
				doctype
				html(lang: "en") do
					head do
						meta(charset: "utf-8")
						meta(name: "viewport", content: "width=device-width, initial-scale=1")
						title { @title }
						meta(name: "csrf-token", content: "abc123def456")
						link(rel: "stylesheet", href: "/assets/application.css", data: { turbo_track: "reload" })
						script(src: "/assets/application.js", type: "module", defer: true, data: { turbo_track: "reload" })
					end

					body(class: "min-h-screen bg-gray-50 text-gray-900", data: { controller: "app" }) do
						header(class: "border-b bg-white") do
							nav(class: "mx-auto flex max-w-7xl items-center gap-6 px-4 py-3", aria: { label: "Main" }) do
								a(href: "/", class: "font-bold text-lg") { "Shop" }
								ul(class: "flex gap-4") do
									NAV.each do |label, path|
										current = path == @current
										li do
											a(
												href: path,
												class: ["rounded px-3 py-2 text-sm", (current ? "bg-gray-900 text-white" : "text-gray-600 hover:bg-gray-100")],
												aria: { current: (current ? "page" : nil) },
											) { label }
										end
									end
								end
							end
						end

						main(class: "mx-auto max-w-7xl px-4 py-8", &)

						footer(class: "border-t py-6 text-center text-sm text-gray-500") do
							plain "© 2026 Shop. All rights reserved."
						end
					end
				end
			end
		end

		class Badge < Phlex::HTML
			VARIANTS = {
				pending: "bg-yellow-100 text-yellow-800",
				paid: "bg-green-100 text-green-800",
				shipped: "bg-blue-100 text-blue-800",
				refunded: "bg-gray-100 text-gray-800",
				cancelled: "bg-red-100 text-red-800",
			}.freeze

			def initialize(status)
				@status = status
			end

			def view_template
				span(class: ["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium", VARIANTS[@status]]) { @status.to_s.capitalize }
			end
		end

		class Button < Phlex::HTML
			VARIANTS = {
				primary: "bg-indigo-600 text-white hover:bg-indigo-500",
				secondary: "bg-white text-gray-900 ring-1 ring-gray-300 hover:bg-gray-50",
				danger: "bg-red-600 text-white hover:bg-red-500",
			}.freeze

			def initialize(href: nil, variant: :primary, size: :md, **attributes)
				@href = href
				@variant = variant
				@size = size
				@attributes = attributes
			end

			def view_template(&)
				classes = ["inline-flex items-center rounded-md font-semibold shadow-sm", VARIANTS[@variant], ((@size == :sm) ? "px-2 py-1 text-xs" : "px-3 py-2 text-sm")]

				if @href
					a(href: @href, class: classes, **@attributes, &)
				else
					button(type: "button", class: classes, **@attributes, &)
				end
			end
		end

		class Avatar < Phlex::HTML
			def initialize(src:, name:, size: 40)
				@src = src
				@name = name
				@size = size
			end

			def view_template
				img(src: @src, alt: @name, width: @size, height: @size, class: "rounded-full", loading: "lazy")
			end
		end

		class Star < Phlex::HTML
			def initialize(filled)
				@filled = filled
			end

			def view_template
				svg(viewBox: "0 0 20 20", fill: "currentColor", class: ["h-4 w-4", (@filled ? "text-yellow-400" : "text-gray-300")], aria: { hidden: true }) do |s|
					s.path(fill_rule: "evenodd", d: "M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401z", clip_rule: "evenodd")
				end
			end
		end

		class Card < Phlex::HTML
			def initialize(**attributes)
				@attributes = attributes
			end

			def view_template(&)
				div(class: "overflow-hidden rounded-lg bg-white shadow", **@attributes, &)
			end
		end
	end

	def self.money(cents)
		"$#{cents / 100}.#{(cents % 100).to_s.rjust(2, '0')}"
	end

	# An admin table: 50 rows with links, status badges, action buttons and Turbo/Stimulus data attributes.
	class Dashboard < Phlex::HTML
		include UI

		def view_template
			Layout(title: "Orders", current: "/orders") do
				div(class: "mb-6 flex items-center justify-between") do
					h1(class: "text-2xl font-semibold") { "Orders" }
					Button(href: "/orders/new") { "New order" }
				end

				Card do
					table(class: "min-w-full divide-y divide-gray-200") do
						thead(class: "bg-gray-50") do
							tr do
								%w[Order Customer Date Items Total Status].each do |heading|
									th(scope: "col", class: "px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-gray-500") { heading }
								end
								th(scope: "col", class: "relative px-4 py-3") { span(class: "sr-only") { "Actions" } }
							end
						end

						tbody(class: "divide-y divide-gray-200 bg-white") do
							ORDERS.each do |order|
								tr(id: "order_#{order.id}", class: ["hover:bg-gray-50", ("opacity-60" if order.status == :cancelled)], data: { controller: "row", row_id_value: order.id }) do
									td(class: "whitespace-nowrap px-4 py-3 text-sm font-medium") do
										a(href: "/orders/#{order.id}", class: "text-indigo-600 hover:underline", data: { turbo_frame: "order_detail" }) { order.number }
									end
									td(class: "px-4 py-3 text-sm") do
										div(class: "font-medium") { order.customer }
										div(class: "text-gray-500") { order.email }
									end
									td(class: "whitespace-nowrap px-4 py-3 text-sm text-gray-500") { time(datetime: order.placed_on) { order.placed_on } }
									td(class: "px-4 py-3 text-sm text-right") { order.items }
									td(class: "px-4 py-3 text-sm text-right font-mono") { Bench.money(order.total_cents) }
									td(class: "px-4 py-3 text-sm") { Badge(order.status) }
									td(class: "whitespace-nowrap px-4 py-3 text-right text-sm") do
										Button(href: "/orders/#{order.id}/edit", variant: :secondary, size: :sm) { "Edit" }
										whitespace
										Button(variant: :danger, size: :sm, data: { action: "row#destroy", confirm: "Delete #{order.number}?" }) { "Delete" }
									end
								end
							end
						end
					end
				end

				nav(class: "mt-4 flex justify-between", aria: { label: "Pagination" }) do
					Button(href: "/orders?page=1", variant: :secondary) { "Previous" }
					Button(href: "/orders?page=3", variant: :secondary) { "Next" }
				end
			end
		end
	end

	# A text-heavy article with escaped user content, code blocks and a comment thread with avatars.
	class Article < Phlex::HTML
		include UI

		def view_template
			Layout(title: POST.title, current: "/") do
				article(class: "prose mx-auto") do
					header do
						h1 { POST.title }
						p(class: "text-sm text-gray-500") do
							plain "By "
							a(href: "/authors/jo-bloggs", rel: "author") { POST.author }
							plain " on "
							time(datetime: POST.published_on) { POST.published_on }
						end
						ul(class: "flex gap-2") do
							POST.tags.each { |tag| li { a(href: "/tags/#{tag}", class: "tag") { "##{tag}" } } }
						end
					end

					POST.sections.each do |part|
						section(id: part.anchor) do
							h2 { a(href: "##{part.anchor}") { part.heading } }
							part.paragraphs.each { |paragraph| p { paragraph } }
							pre { code(class: "language-ruby") { part.code } } if part.code
						end
					end
				end

				section(class: "mx-auto mt-12 max-w-2xl", aria: { labelledby: "comments" }) do
					h2(id: "comments") { "#{COMMENTS.length} comments" }

					COMMENTS.each do |comment|
						div(id: "comment_#{comment.id}", class: "flex gap-3 py-4") do
							Avatar(src: comment.avatar, name: comment.author)
							div do
								div(class: "flex items-center gap-2 text-sm") do
									strong { comment.author }
									time(datetime: comment.posted_at, class: "text-gray-500") { comment.posted_at }
								end
								p(class: "mt-1") { comment.body }
								Button(variant: :secondary, size: :sm, data: { action: "comment#like", comment_id_param: comment.id }) { "♥ #{comment.likes}" }
							end
						end
					end
				end
			end
		end
	end

	# A product grid: 60 cards of nested components, inline SVG ratings and conditional attributes.
	class Catalogue < Phlex::HTML
		include UI

		def view_template
			Layout(title: "Products", current: "/products") do
				div(class: "grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4") do
					PRODUCTS.each do |product|
						Card(id: "product_#{product.id}", data: { controller: "product", product_id_value: product.id }) do
							a(href: "/products/#{product.id}", class: "block") do
								img(src: product.image, alt: product.name, class: "aspect-square w-full object-cover", loading: "lazy")
							end

							div(class: "p-4") do
								p(class: "text-xs uppercase text-gray-500") { product.brand }
								h3(class: "mt-1 font-medium") { a(href: "/products/#{product.id}") { product.name } }

								div(class: "mt-2 flex items-center gap-1", aria: { label: "#{product.rating} out of 5 stars" }) do
									5.times { |i| Star(i < product.rating) }
									span(class: "ml-1 text-xs text-gray-500") { "(#{product.reviews})" }
								end

								div(class: "mt-2 flex gap-1") do
									product.colors.each do |color|
										span(class: ["h-4 w-4 rounded-full border", "bg-#{color}-500"], title: color)
									end
								end

								p(class: "mt-3") do
									if product.sale_cents
										span(class: "font-bold text-red-600") { Bench.money(product.sale_cents) }
										whitespace
										del(class: "text-sm text-gray-500") { Bench.money(product.price_cents) }
									else
										span(class: "font-bold") { Bench.money(product.price_cents) }
									end
								end

								Button(
									variant: (product.in_stock ? :primary : :secondary),
									disabled: !product.in_stock,
									data: { action: "cart#add", product_id_param: product.id },
								) { product.in_stock ? "Add to cart" : "Sold out" }
							end
						end
					end
				end
			end
		end
	end

	# A settings form: labelled inputs, hints and errors wired up with ARIA, a 120-option select and checkboxes.
	class SettingsForm < Phlex::HTML
		include UI

		def view_template
			Layout(title: "Settings", current: "/settings") do
				form(action: "/settings", method: "post", class: "space-y-6", data: { controller: "form", turbo: false }) do
					input(type: "hidden", name: "authenticity_token", value: "abc123def456", autocomplete: "off")
					input(type: "hidden", name: "_method", value: "patch")

					FIELDS.each do |field|
						id = field.name.tr("[]", "_").delete_suffix("_")
						hint_id = "#{id}_hint"
						error_id = "#{id}_error"

						div(class: ["field", ("field-with-errors" if field.error)]) do
							label(for: id, class: "block text-sm font-medium") do
								plain field.label
								abbr(title: "required") { "*" } if field.required
							end
							input(
								type: field.type,
								id:,
								name: field.name,
								value: field.value,
								required: field.required,
								class: ["mt-1 block w-full rounded-md border-gray-300 shadow-sm", ("border-red-500" if field.error)],
								aria: { describedby: (field.error ? "#{hint_id} #{error_id}" : hint_id), invalid: (field.error ? "true" : nil) },
							)
							p(id: hint_id, class: "mt-1 text-sm text-gray-500") { field.hint }
							p(id: error_id, class: "mt-1 text-sm text-red-600") { "#{field.label} #{field.error}" } if field.error
						end
					end

					div(class: "field") do
						label(for: "user_country", class: "block text-sm font-medium") { "Country" }
						select(id: "user_country", name: "user[country]", class: "mt-1 block w-full") do
							COUNTRIES.each do |value, name|
								option(value:, selected: value == "c42") { name }
							end
						end
					end

					fieldset do
						legend(class: "text-sm font-medium") { "Notifications" }
						%w[comments mentions follows orders newsletter].each_with_index do |kind, i|
							div(class: "flex items-center gap-2") do
								input(type: "checkbox", id: "user_notify_#{kind}", name: "user[notify][]", value: kind, checked: i.even?)
								label(for: "user_notify_#{kind}") { kind.capitalize }
							end
						end
					end

					div(class: "flex justify-end gap-3") do
						Button(href: "/", variant: :secondary) { "Cancel" }
						button(type: "submit", class: "btn btn-primary") { "Save" }
					end
				end
			end
		end
	end
end
