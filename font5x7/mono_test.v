module font5x7

fn test_mono_glyphs_have_fixed_cells_and_empty_spacing() {
	for code in 0 .. 78 {
		rows := mono_bitmap(code)
		assert rows.len == mono_height
		assert rows[mono_height - 1] == 0
		for row in 0 .. height {
			assert rows[row] == bitmap(code)[row] << 1
			assert rows[row] & 1 == 0
		}
	}
	assert mono_bitmap_for_rune('€'.runes()[0]) == mono_bitmap(53)
	assert mono_pixel_on(1, 0, 1)
	assert !mono_pixel_on(1, 0, mono_width - 1)
	assert !mono_pixel_on(1, mono_height - 1, 1)
}

fn test_mono_lines_have_equal_advance_for_all_characters() {
	latin := mono_line('ABC')
	unicode := mono_line('ä€→')
	assert latin.width == 3 * mono_width
	assert unicode.width == latin.width
	assert latin.height == mono_height
	assert unicode.pixels.len == unicode.width * unicode.height
	assert unicode.pixels.any(it == 1)
	for row in 0 .. mono_height {
		for index in 0 .. 3 {
			assert unicode.pixels[row * unicode.width + index * mono_width + mono_width - 1] == 0
		}
	}
	assert mono_line('').width == 0
	assert mono_line('').pixels.len == 0
}
