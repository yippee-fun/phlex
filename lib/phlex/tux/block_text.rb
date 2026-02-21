# frozen_string_literal: true

class Phlex::Tux::BlockText < Phlex::TUI
		HANGING_LEFT_PUNCTUATION = {
				'"' => true,
				"'" => true,
				"“" => true,
				"‘" => true,
		}.freeze

		HANGING_RIGHT_PUNCTUATION = {
				'"' => true,
				"'" => true,
				"”" => true,
				"’" => true,
				"," => true,
				"." => true,
				"!" => true,
				"?" => true,
				":" => true,
				";" => true,
		}.freeze

		BITS = {
				" " => 0,
				"▀" => 2,
				"▄" => 1,
				"█" => 3,
		}.freeze

		BIT_TO_CHAR = [" ", "▄", "▀", "█"].freeze
		CACHE_LIMIT = 64

		def initialize(
				text:,
				font:,
				letter_spacing: 0,
				line_height: 1.0,
				glyph_offset_y: 0,
				hanging_punctuation: false,
				text_align: :left,
				text_wrap: :word,
				width: :fit,
				height: :fit,
				min_width: nil,
				min_height: nil,
				max_width: nil,
				max_height: nil
		)
				@text = text.to_s
				assign_font!(font)
				@letter_spacing = normalize_integer(letter_spacing, :letter_spacing)
				@line_height = normalize_line_height(line_height)
				@glyph_offset_y = normalize_integer(glyph_offset_y, :glyph_offset_y)
				@hanging_punctuation = normalize_boolean(hanging_punctuation, :hanging_punctuation)
				@text_align = normalize_text_align(text_align)
				@text_wrap = normalize_text_wrap(text_wrap)
				@width = normalize_dimension(width, :width)
				@height = normalize_dimension(height, :height)
				@min_width = min_width
				@min_height = min_height
				@max_width = max_width
				@max_height = max_height

				reset_all_caches!
		end

		def text=(value)
				@text = value.to_s
				reset_render_caches!
				request_render!
		end

		def font=(value)
				assign_font!(value)
				reset_all_caches!
				request_render!
		end

		def letter_spacing=(value)
				@letter_spacing = normalize_integer(value, :letter_spacing)
				reset_render_caches!
				request_render!
		end

		def line_height=(value)
				@line_height = normalize_line_height(value)
				reset_render_caches!
				request_render!
		end

		def glyph_offset_y=(value)
				@glyph_offset_y = normalize_integer(value, :glyph_offset_y)
				reset_all_caches!
				request_render!
		end

		def hanging_punctuation=(value)
				@hanging_punctuation = normalize_boolean(value, :hanging_punctuation)
				reset_render_caches!
				request_render!
		end

		def text_align=(value)
				@text_align = normalize_text_align(value)
				reset_render_caches!
				request_render!
		end

		def text_wrap=(value)
				@text_wrap = normalize_text_wrap(value)
				reset_render_caches!
				request_render!
		end

		def view_template
				canvas(
						width: @width,
						height: @height,
						min_width: @min_width,
						min_height: @min_height,
						max_width: @max_width,
						max_height: @max_height,
						measure: method(:measure_block_text)
				) do |surface, width, height|
						draw_block_text(surface:, width:, height:)
				end
		end

		private def draw_block_text(surface:, width:, height:)
				rows = rendered_rows(width)
				visible_height = (Integer === height) ? height : nil
				surface.blit_rows(row: 0, col: 0, rows:, limit: visible_height)

				nil
		end

		private def measure_block_text(width, _height)
				rows = rendered_rows(width)
				max_width = 0

				index = 0
				while index < rows.length
						row_width = rows[index].length
						max_width = row_width if row_width > max_width
						index += 1
				end

				[max_width, rows.length]
		end

		private def rendered_rows(width)
				key = [@text, @font.object_id, width, @letter_spacing, @line_height, @glyph_offset_y, @hanging_punctuation, @text_align, @text_wrap]
				cached = @render_cache[key]
				return cached if cached

				content_width = content_width_for_wrap(width)
				lines = wrapped_lines_for(content_width)
				composed_rows = []

				line_index = 0
				while line_index < lines.length
						line_content, left_hanging, right_hanging = extract_hanging_punctuation(lines[line_index])
						line_rows, line_width = render_line_rows(line_content)
						align_rows!(line_rows, line_width, content_width)
						line_rows = apply_hanging_punctuation_padding(line_rows, left_hanging:, right_hanging:)

						if composed_rows.empty?
								composed_rows = line_rows
						else
								line_gap = computed_line_gap(line_rows.length)

								if line_gap >= 0
										composed_rows.concat(gap_rows(line_gap))
										composed_rows.concat(line_rows)
								else
										merge_blocks_vertically!(composed_rows, line_rows, -line_gap)
								end
						end

						line_index += 1
				end

				store_cache!(@render_cache, key, composed_rows)
				composed_rows
		end

		private def content_width_for_wrap(width)
				return nil if width.nil?
				return width unless @hanging_punctuation

				[width - (hanging_gutter_width * 2), 0].max
		end

		private def apply_hanging_punctuation_padding(rows, left_hanging:, right_hanging:)
				return rows unless @hanging_punctuation

				gutter_width = hanging_gutter_width
				left_rows = hanging_rows(left_hanging, side: :left, width: gutter_width)
				right_rows = hanging_rows(right_hanging, side: :right, width: gutter_width)
				result = []
				i = 0
				while i < rows.length
						left = left_rows ? left_rows[i] : (" " * gutter_width)
						right = right_rows ? right_rows[i] : (" " * gutter_width)
						result << (left + rows[i] + right)
						i += 1
				end
				result
		end

		private def extract_hanging_punctuation(graphemes)
				return [graphemes, nil, nil] unless @hanging_punctuation
				return [graphemes, nil, nil] if graphemes.empty?

				left_hanging = nil
				right_hanging = nil
				left_index = 0
				right_index = graphemes.length - 1

				if left_index <= right_index && HANGING_LEFT_PUNCTUATION[graphemes[left_index]]
						left_hanging = graphemes[left_index]
						left_index += 1
				end

				if left_index <= right_index && HANGING_RIGHT_PUNCTUATION[graphemes[right_index]]
						right_hanging = graphemes[right_index]
						right_index -= 1
				end

				content = if left_index <= right_index
						graphemes[left_index..right_index]
				else
						[]
				end

				[content || [], left_hanging, right_hanging]
		end

		private def hanging_rows(character, side:, width:)
				return nil unless character

				glyph_rows, glyph_width_value, _glyph_masks = glyph_rows_masks_and_width(character)
				padding = [width - glyph_width_value, 0].max
				pad = " " * padding
				result = []
				i = 0
				while i < glyph_rows.length
						row = glyph_rows[i]
						result << if side == :left
								(pad + row)
						else
								(row + pad)
						end
						i += 1
				end
				result
		end

		private def hanging_gutter_width
				@font.space_width
		end

		private def wrapped_lines_for(width)
				key = [@text, @font.object_id, width, @text_wrap, @letter_spacing]
				cached = @wrap_cache[key]
				return cached if cached

				raw_lines = split_lines_to_graphemes(@text)
				if width.nil? || @text_wrap == :none || width <= 0
						store_cache!(@wrap_cache, key, raw_lines)
						return raw_lines
				end

				wrapped = []
				line_index = 0
				while line_index < raw_lines.length
						line_graphemes = raw_lines[line_index]

						case @text_wrap
						in :word
								wrapped.concat(wrap_word_graphemes(line_graphemes, width))
						in :pretty
								wrapped.concat(wrap_pretty_graphemes(line_graphemes, width))
						in :grapheme
								wrapped.concat(wrap_grapheme_segments(line_graphemes, width).map { |segment| segment[0] })
						end

						line_index += 1
				end

				wrapped = [[]] if wrapped.empty?
				store_cache!(@wrap_cache, key, wrapped)
				wrapped
		end

		private def wrap_pretty_graphemes(graphemes, width)
				lines = wrap_word_graphemes(graphemes, width)
				return lines if lines.length < 2

				i = 0
				while i + 1 < lines.length
						left = lines[i]
						right = lines[i + 1]

						if !left.empty? && !right.empty?
								balanced = rebalance_pair(left, right, width)
								lines[i] = balanced[0]
								lines[i + 1] = balanced[1]
						end

						i += 1
				end

				lines
		end

		private def rebalance_pair(left, right, width)
				current_left = left
				current_right = right
				best_score = pair_pretty_score(current_left, current_right, width)

				moved_from_right = move_leading_word_to_previous(current_left, current_right, width)
				unless moved_from_right.nil?
						score = pair_pretty_score(moved_from_right[0], moved_from_right[1], width)
						if score < best_score
								current_left = moved_from_right[0]
								current_right = moved_from_right[1]
								best_score = score
						end
				end

				moved_from_left = move_trailing_word_to_next(current_left, current_right, width)
				unless moved_from_left.nil?
						score = pair_pretty_score(moved_from_left[0], moved_from_left[1], width)
						if score < best_score
								current_left = moved_from_left[0]
								current_right = moved_from_left[1]
						end
				end

				[current_left, current_right]
		end

		private def move_leading_word_to_previous(left, right, width)
				segment, remainder = take_leading_word(right)
				return nil if segment.empty?

				next_left = append_with_single_space(left, segment)
				return nil if line_width(next_left) > width

				[next_left, remainder]
		end

		private def move_trailing_word_to_next(left, right, width)
				remainder, segment = take_trailing_word(left)
				return nil if segment.empty?

				next_right = prepend_with_single_space(right, segment)
				return nil if line_width(next_right) > width
				return nil if remainder.empty?

				[remainder, next_right]
		end

		private def take_leading_word(graphemes)
				return [[], []] if graphemes.empty?

				i = 0
				while i < graphemes.length && whitespace_grapheme?(graphemes[i])
						i += 1
				end

				start = i
				while i < graphemes.length && !whitespace_grapheme?(graphemes[i])
						i += 1
				end

				segment = graphemes[start...i] || []
				remainder = graphemes[i..] || []
				remainder = trim_leading_whitespace(remainder)
				[segment, remainder]
		end

		private def take_trailing_word(graphemes)
				return [[], []] if graphemes.empty?

				i = graphemes.length - 1
				while i >= 0 && whitespace_grapheme?(graphemes[i])
						i -= 1
				end
				return [[], []] if i < 0

				finish = i
				while i >= 0 && !whitespace_grapheme?(graphemes[i])
						i -= 1
				end

				segment = graphemes[(i + 1)..finish] || []
				remainder = graphemes[0..i] || []
				remainder = trim_trailing_whitespace_graphemes(remainder)
				[remainder, segment]
		end

		private def append_with_single_space(left, segment)
				result = left.dup
				if !result.empty? && !segment.empty? && !whitespace_grapheme?(result[-1]) && !whitespace_grapheme?(segment[0])
						result << " "
				end
				result.concat(segment)
				result
		end

		private def prepend_with_single_space(right, segment)
				result = segment.dup
				if !result.empty? && !right.empty? && !whitespace_grapheme?(result[-1]) && !whitespace_grapheme?(right[0])
						result << " "
				end
				result.concat(right)
				result
		end

		private def trim_leading_whitespace(graphemes)
				i = 0
				while i < graphemes.length && whitespace_grapheme?(graphemes[i])
						i += 1
				end
				graphemes[i..] || []
		end

		private def trim_trailing_whitespace_graphemes(graphemes)
				i = graphemes.length - 1
				while i >= 0 && whitespace_grapheme?(graphemes[i])
						i -= 1
				end
				return [] if i < 0

				graphemes[0..i] || []
		end

		private def pair_pretty_score(left, right, width)
				left_width = line_width(left)
				right_width = line_width(right)
				raggedness = (left_width - right_width).abs
				widow_penalty = (right_width * 4 < width) ? 6 : 0
				raggedness + widow_penalty
		end

		private def line_width(graphemes)
				profile_for_graphemes(graphemes)[1]
		end

		private def wrap_word_graphemes(graphemes, width)
				tokens = tokenize_word_graphemes(graphemes)
				result = []
				current = []
				current_profile = empty_profile
				pending_spaces = nil

				token_index = 0
				while token_index < tokens.length
						token = tokens[token_index]
						token_index += 1

						if token[2]
								pending_spaces = token unless current.empty?
								next
						end

						if current.empty?
								if token[1][1] <= width
										current = token[0].dup
										current_profile = token[1]
								else
										segments = wrap_grapheme_segments(token[0], width)
										if segments.length == 1
												current = segments[0][0]
												current_profile = segments[0][1]
										else
												last_index = segments.length - 1
												i = 0
												while i < last_index
														result << segments[i][0]
														i += 1
												end
												current = segments[last_index][0]
												current_profile = segments[last_index][1]
										end
								end
								pending_spaces = nil
								next
						end

						candidate_profile = current_profile
						unless pending_spaces.nil?
								candidate_profile = concat_profiles(candidate_profile, pending_spaces[1])
						end
						candidate_profile = concat_profiles(candidate_profile, token[1])

						if candidate_profile[1] <= width
								unless pending_spaces.nil?
										current.concat(pending_spaces[0])
								end
								current.concat(token[0])
								current_profile = candidate_profile
								pending_spaces = nil
								next
						end

						result << current
						if token[1][1] <= width
								current = token[0].dup
								current_profile = token[1]
						else
								segments = wrap_grapheme_segments(token[0], width)
								if segments.length == 1
										current = segments[0][0]
										current_profile = segments[0][1]
								else
										last_index = segments.length - 1
										i = 0
										while i < last_index
												result << segments[i][0]
												i += 1
										end
										current = segments[last_index][0]
										current_profile = segments[last_index][1]
								end
						end
						pending_spaces = nil
				end

				result << current unless current.empty?
				result = [[]] if result.empty?
				result
		end

		private def tokenize_word_graphemes(graphemes)
				return [] if graphemes.empty?

				tokens = []
				start = 0
				current_space = whitespace_grapheme?(graphemes[0])
				i = 1

				while i < graphemes.length
						is_space = whitespace_grapheme?(graphemes[i])
						if is_space != current_space
								segment = graphemes[start...i]
								tokens << [segment, profile_for_graphemes(segment), current_space]
								start = i
								current_space = is_space
						end
						i += 1
				end

				segment = graphemes[start..] || []
				tokens << [segment, profile_for_graphemes(segment), current_space]
				tokens
		end

		private def wrap_grapheme_segments(graphemes, width)
				return [[[], empty_profile]] if graphemes.empty?

				segments = []
				current = []
				current_profile = empty_profile
				i = 0

				while i < graphemes.length
						grapheme = graphemes[i]
						glyph_width = glyph_width(grapheme)
						next_profile = single_profile(glyph_width)

						if current.empty?
								current = [grapheme]
								current_profile = next_profile
								i += 1
								next
						end

						candidate = concat_profiles(current_profile, next_profile)
						if candidate[1] <= width
								current << grapheme
								current_profile = candidate
								i += 1
								next
						end

						segments << [current, current_profile]
						current = [grapheme]
						current_profile = next_profile
						i += 1
				end

				segments << [current, current_profile] unless current.empty?
				segments = [[[], empty_profile]] if segments.empty?
				segments
		end

		private def render_line_rows(graphemes)
				return [blank_line_rows, 0] if graphemes.empty?

				if @letter_spacing >= 0
						render_line_rows_with_spacing(graphemes)
				else
						render_line_rows_with_overlap(graphemes)
				end
		end

		private def render_line_rows_with_spacing(graphemes)
				rows = nil
				line_width = 0
				gap = (@letter_spacing > 0) ? (" " * @letter_spacing) : nil
				i = 0

				while i < graphemes.length
						glyph_rows, glyph_width, _glyph_masks = glyph_rows_masks_and_width(graphemes[i])

						if rows.nil?
								rows = duplicate_rows(glyph_rows)
								line_width = glyph_width
								i += 1
								next
						end

						row_index = 0
						while row_index < rows.length
								rows[row_index] << gap if gap
								rows[row_index] << glyph_rows[row_index]
								row_index += 1
						end
						line_width += @letter_spacing + glyph_width
						i += 1
				end

				[rows || blank_line_rows, line_width]
		end

		private def render_line_rows_with_overlap(graphemes)
				row_masks = nil
				line_width = 0
				previous_width = 0
				i = 0

				while i < graphemes.length
						_glyph_rows, glyph_width, glyph_masks = glyph_rows_masks_and_width(graphemes[i])

						if row_masks.nil?
								row_masks = duplicate_masks(glyph_masks)
								line_width = glyph_width
								previous_width = glyph_width
								i += 1
								next
						end

						overlap = [-@letter_spacing, previous_width, glyph_width].min
						row_index = 0
						while row_index < row_masks.length
								row_masks[row_index] = merge_masks_horizontally(row_masks[row_index], glyph_masks[row_index], overlap)
								row_index += 1
						end

						line_width += glyph_width - overlap
						previous_width = glyph_width
						i += 1
				end

				[rows_from_masks(row_masks || []), line_width]
		end

		private def duplicate_rows(rows)
				result = []
				i = 0
				while i < rows.length
						result << rows[i].dup
						i += 1
				end
				result
		end

		private def duplicate_masks(masks)
				result = []
				i = 0

				while i < masks.length
						result << masks[i].dup
						i += 1
				end

				result
		end

		private def align_rows!(rows, line_width, width)
				return unless Integer === width

				padding = case @text_align
				in :left
						0
				in :center
						[(width - line_width) / 2, 0].max
				in :right
						[width - line_width, 0].max
				end

				return if padding <= 0

				prefix = " " * padding
				i = 0
				while i < rows.length
						rows[i] = prefix + rows[i]
						i += 1
				end
		end

		private def merge_blocks_vertically!(top_rows, bottom_rows, overlap)
				effective_overlap = [overlap, top_rows.length, bottom_rows.length].min
				if effective_overlap <= 0
						top_rows.concat(bottom_rows)
						return top_rows
				end

				start = top_rows.length - effective_overlap
				i = 0
				while i < effective_overlap
						top_rows[start + i] = merge_row_by_mask(top_rows[start + i], bottom_rows[i])
						i += 1
				end

				i = effective_overlap
				while i < bottom_rows.length
						top_rows << bottom_rows[i]
						i += 1
				end

				top_rows
		end

		private def merge_row_horizontally(left, right, overlap)
				effective_overlap = [overlap, left.length, right.length].min
				return left + right if effective_overlap <= 0

				prefix = left[0, left.length - effective_overlap] || ""
				left_overlap = left[-effective_overlap, effective_overlap] || ""
				right_overlap = right[0, effective_overlap] || ""
				suffix = right[effective_overlap..] || ""

				prefix + merge_columns(left_overlap, right_overlap) + suffix
		end

		private def merge_masks_horizontally(left, right, overlap)
				effective_overlap = [overlap, left.length, right.length].min
				return left + right if effective_overlap <= 0

				prefix_length = left.length - effective_overlap
				suffix_start = effective_overlap
				suffix_length = right.length - effective_overlap
				result = Array.new(prefix_length + effective_overlap + suffix_length, 0)

				i = 0
				while i < prefix_length
						result[i] = left[i]
						i += 1
				end

				i = 0
				while i < effective_overlap
						result[prefix_length + i] = left[prefix_length + i] | right[i]
						i += 1
				end

				i = 0
				while i < suffix_length
						result[prefix_length + effective_overlap + i] = right[suffix_start + i]
						i += 1
				end

				result
		end

		private def merge_row_by_mask(left, right)
				width = [left.length, right.length].max
				left_value = left.ljust(width)
				right_value = right.ljust(width)
				merge_columns(left_value, right_value)
		end

		private def merge_columns(left, right)
				length = [left.length, right.length].min
				result = +""

				i = 0
				while i < length
						left_bit = BITS[left[i]] || 0
						right_bit = BITS[right[i]] || 0
						result << BIT_TO_CHAR[left_bit | right_bit]
						i += 1
				end

				result
		end

		private def rows_from_masks(masks)
				return blank_line_rows if masks.empty?

				rows = Array.new(masks.length)
				i = 0

				while i < masks.length
						mask_row = masks[i]
						row = +""
						j = 0
						while j < mask_row.length
								row << BIT_TO_CHAR[mask_row[j]]
								j += 1
						end
						rows[i] = row
						i += 1
				end

				rows
		end

		private def glyph_rows_masks_and_width(character)
				key = [character, @glyph_offset_y]
				cached = @glyph_cache[key]
				return cached if cached

				glyph = @font.glyph_for(character)
				glyph_width = glyph.width
				rows = glyph.rows
				masks = glyph.masks

				if @glyph_offset_y.positive?
						rows = Array.new(@glyph_offset_y) { " " * glyph_width } + rows
						masks = Array.new(@glyph_offset_y) { Array.new(glyph_width, 0) } + masks
				elsif @glyph_offset_y.negative?
						rows += Array.new(-@glyph_offset_y) { " " * glyph_width }
						masks += Array.new(-@glyph_offset_y) { Array.new(glyph_width, 0) }
				end

				value = [rows, glyph_width, masks]
				store_cache!(@glyph_cache, key, value)
				value
		end

		private def blank_line_rows
				@blank_line_rows ||= Array.new(base_row_count + @glyph_offset_y.abs) { "" }
		end

		private def base_row_count
				@font.row_count
		end

		private def glyph_width(character)
				cached = @glyph_width_cache[character]
				return cached if cached

				width = @font.glyph_for(character).width
				@glyph_width_cache[character] = width
				width
		end

		private def profile_for_graphemes(graphemes)
				return empty_profile if graphemes.empty?

				first_width = glyph_width(graphemes[0])
				total = first_width
				previous = first_width
				i = 1

				while i < graphemes.length
						current = glyph_width(graphemes[i])
						total = appended_width(total, previous, current)
						previous = current
						i += 1
				end

				[graphemes.length, total, first_width, previous]
		end

		private def concat_profiles(left, right)
				return right if left[0].zero?
				return left if right[0].zero?

				link = transition_increment(left[3], right[2])
				[
						left[0] + right[0],
						left[1] + link + (right[1] - right[2]),
						left[2],
						right[3],
				]
		end

		private def appended_width(current_width, previous_width, next_width)
				current_width + transition_increment(previous_width, next_width)
		end

		private def transition_increment(previous_width, next_width)
				if @letter_spacing >= 0
						@letter_spacing + next_width
				else
						overlap = [-@letter_spacing, previous_width, next_width].min
						next_width - overlap
				end
		end

		private def empty_profile
				[0, 0, 0, 0]
		end

		private def single_profile(width)
				[1, width, width, width]
		end

		private def split_lines_to_graphemes(text)
				raw_lines = text.split("\n", -1)
				result = []
				i = 0

				while i < raw_lines.length
						result << split_graphemes(raw_lines[i])
						i += 1
				end

				result
		end

		private def split_graphemes(text)
				result = []
				Phlex::TUI::TextWidth.each_grapheme(text) do |grapheme|
						result << grapheme
				end
				result
		end

		private def whitespace_grapheme?(grapheme)
				/\A\s\z/.match?(grapheme)
		end

		private def gap_rows(amount)
				cached = @gap_rows_cache[amount]
				return cached if cached

				rows = Array.new(amount) { "" }
				@gap_rows_cache[amount] = rows
				rows
		end

		private def computed_line_gap(line_row_count)
				((line_row_count * @line_height) - line_row_count).round
		end

		private def store_cache!(cache, key, value)
				if cache.length >= CACHE_LIMIT
						oldest_key = cache.each_key.first
						cache.delete(oldest_key) unless oldest_key.nil?
				end

				cache[key] = value
		end

		private def reset_all_caches!
				@glyph_cache = {}
				@glyph_width_cache = {}
				@render_cache = {}
				@wrap_cache = {}
				@gap_rows_cache = {}
				@blank_line_rows = nil
		end

		private def reset_render_caches!
				@render_cache = {}
				@wrap_cache = {}
		end

		private def assign_font!(font)
				@font = normalize_font(font)
		end

		private def normalize_font(font)
				case font
				in Phlex::TUI::CompiledFont
						font
				else
						raise ArgumentError, "font must be a Phlex::TUI::CompiledFont"
				end
		end

		private def normalize_integer(value, name)
				unless Integer === value
						raise ArgumentError, "#{name} must be an Integer"
				end

				value
		end

		private def normalize_line_height(value)
				unless Numeric === value
						raise ArgumentError, "line_height must be a Numeric"
				end

				line_height = value.to_f
				if !line_height.finite? || line_height.negative?
						raise ArgumentError, "line_height must be a finite Numeric >= 0"
				end

				line_height
		end

		private def normalize_boolean(value, name)
				unless value == true || value == false
						raise ArgumentError, "#{name} must be true or false"
				end

				value
		end

		private def normalize_text_align(value)
				case value
				in :left | :center | :right
						value
				else
						raise ArgumentError, "text_align must be :left, :center, or :right"
				end
		end

		private def normalize_text_wrap(value)
				case value
				in :word | :grapheme | :none | :pretty
						value
				else
						raise ArgumentError, "text_wrap must be :word, :pretty, :grapheme, or :none"
				end
		end

		private def normalize_dimension(value, name)
				return value if Integer === value && value >= 0
				return value if value == :fit || value == :grow

				raise ArgumentError, "#{name} must be an Integer >= 0, :fit, or :grow"
		end
end
