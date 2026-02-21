# frozen_string_literal: true

class Phlex::TUI::CompiledFont
		Glyph = Data.define(:rows, :masks, :width)
		MASK_BITS = {
				" " => 0,
				"▄" => 1,
				"▀" => 2,
				"█" => 3,
		}.freeze

		def initialize(glyphs)
				unless Hash === glyphs
						raise ArgumentError, "font must be a Hash"
				end
				raise ArgumentError, "font must include at least one glyph" if glyphs.empty?

				compiled = {}
				row_count = nil
				fallback_width = nil

				glyphs.each do |key, glyph_rows|
						unless String === key && !key.empty?
								raise ArgumentError, "font keys must be non-empty Strings"
						end

						unless Array === glyph_rows && !glyph_rows.empty?
								raise ArgumentError, "font glyphs must be non-empty Arrays"
						end

						glyph_row_count = glyph_rows.length
						if row_count.nil?
								row_count = glyph_row_count
						elsif glyph_row_count != row_count
								raise ArgumentError, "all glyphs must have the same row count"
						end

						glyph_width = nil
						i = 0
						while i < glyph_rows.length
								row = glyph_rows[i]
								unless String === row
										raise ArgumentError, "font glyph rows must be Strings"
								end

								row_width = row.length
								if glyph_width.nil?
										glyph_width = row_width
								elsif row_width != glyph_width
										raise ArgumentError, "all rows in a glyph must have the same width"
								end

								i += 1
						end

						frozen_rows = glyph_rows.map { |row| row.dup.freeze }.freeze
						compiled[key] = Glyph.new(rows: frozen_rows, masks: compile_masks(frozen_rows, glyph_width).freeze, width: glyph_width)

						if fallback_width.nil? || key == "?"
								fallback_width = glyph_width
						end
				end

				@glyphs = compiled.freeze
				@row_count = row_count
				@fallback_glyph = @glyphs["?"] || blank_glyph(width: fallback_width || 1)

				space = @glyphs[" "]
				@space_width = space ? space.width : @fallback_glyph.width
		end

		attr_reader :glyphs
		attr_reader :row_count
		attr_reader :space_width

		def glyph_for(character)
				@glyphs[character] || @fallback_glyph
		end

		private def compile_masks(rows, width)
				masks = Array.new(rows.length)
				i = 0

				while i < rows.length
						row = rows[i]
						row_masks = Array.new(width, 0)
						col = 0

						while col < width
								row_masks[col] = MASK_BITS[row[col]] || 0

								col += 1
						end

						masks[i] = row_masks.freeze
						i += 1
				end

				masks
		end

		private def blank_glyph(width:)
				rows = Array.new(@row_count || 1) { (" " * width).freeze }.freeze
				masks = Array.new(rows.length) { Array.new(width, 0).freeze }.freeze
				Glyph.new(rows:, masks:, width:)
		end
end
