module font5x7

import os

fn test_unicode_text_encodes_to_stable_glyph_codes() {
	assert encode('Aa0/+-.,') == [1, 1, 27, 37, 38, 39, 40, 41]
	assert encode('äöüÄÖÜß') == [42, 43, 44, 45, 46, 47, 48]
	assert encode('éñç$€£¥@&?') == [49, 50, 51, 52, 53, 54, 55, 56, 57, 58]
	assert encode(':;\\()[]%#*=_°\'"↑↓←→') == [59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
		70, 71, 72, 73, 74, 75, 76, 77]
	assert encode('🙂') == [58]
}

fn test_each_glyph_is_a_seven_byte_five_pixel_bitmap() {
	for code in 0 .. 78 {
		rows := bitmap(code)
		assert rows.len == height
		for row in rows {
			assert row <= 31
		}
		if code != 0 {
			assert rows.any(it != 0)
		}
	}
	assert pixel_on(1, 0, 1)
	assert !pixel_on(1, 0, 0)
	assert !pixel_on(1, -1, 0)
	assert !pixel_on(1, 0, width)
	assert bitmap_for_rune('ä'.runes()[0]) == bitmap(42)
}

fn hud_shader_rows(source string, name string, count int) []int {
	declaration := 'const int ${name}[${count}] = int[]('
	assert source.contains(declaration)
	body := source.all_after(declaration).all_before(');')
	mut rows := []int{}
	for line in body.split_into_lines() {
		for token in line.all_before('//').replace(',', ' ').fields() {
			rows << token.int()
		}
	}
	assert rows.len == count
	return rows
}

fn test_hud_shader_and_reusable_font_have_identical_rows() {
	source := os.read_file(os.join_path(@VMODROOT, 'shaders', 'hud.vert')) or {
		panic(err)
	}
	letters := hud_shader_rows(source, 'character_letter_rows', 182)
	digits := hud_shader_rows(source, 'character_digit_rows', 70)
	extended := hud_shader_rows(source, 'character_extended_rows', 252)
	for code in 1 .. 27 {
		for row in 0 .. height {
			assert int(bitmap(code)[row]) == letters[(code - 1) * height + row]
		}
	}
	for code in 27 .. 37 {
		for row in 0 .. height {
			assert int(bitmap(code)[row]) == digits[(code - 27) * height + row]
		}
	}
	for code in 42 .. 78 {
		for row in 0 .. height {
			assert int(bitmap(code)[row]) == extended[(code - 42) * height + row]
		}
	}
}
