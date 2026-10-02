module font5x7

// Stable glyph codes shared with shaders/hud.vert. Each of the seven bytes
// contains five pixels in its low bits, with bit 4 at the left edge.
pub const width = 5
pub const height = 7

const letter_rows = [
	u8(14), 17, 17, 31, 17, 17, 17, // A
	30, 17, 17, 30, 17, 17, 30, // B
	15, 16, 16, 16, 16, 16, 15, // C
	30, 17, 17, 17, 17, 17, 30, // D
	31, 16, 16, 30, 16, 16, 31, // E
	31, 16, 16, 30, 16, 16, 16, // F
	15, 16, 16, 23, 17, 17, 15, // G
	17, 17, 17, 31, 17, 17, 17, // H
	14, 4, 4, 4, 4, 4, 14, // I
	1, 1, 1, 1, 17, 17, 14, // J
	17, 18, 20, 24, 20, 18, 17, // K
	16, 16, 16, 16, 16, 16, 31, // L
	17, 27, 21, 21, 17, 17, 17, // M
	17, 25, 21, 19, 17, 17, 17, // N
	14, 17, 17, 17, 17, 17, 14, // O
	30, 17, 17, 30, 16, 16, 16, // P
	14, 17, 17, 17, 21, 18, 13, // Q
	30, 17, 17, 30, 20, 18, 17, // R
	15, 16, 16, 14, 1, 1, 30, // S
	31, 4, 4, 4, 4, 4, 4, // T
	17, 17, 17, 17, 17, 17, 14, // U
	17, 17, 17, 17, 17, 10, 4, // V
	17, 17, 17, 21, 21, 21, 10, // W
	17, 17, 10, 4, 10, 17, 17, // X
	17, 17, 10, 4, 4, 4, 4, // Y
	31, 1, 2, 4, 8, 16, 31, // Z
]

const digit_rows = [
	u8(14), 17, 19, 21, 25, 17, 14, // 0
	4, 12, 4, 4, 4, 4, 14, // 1
	14, 17, 1, 2, 4, 8, 31, // 2
	30, 1, 1, 14, 1, 1, 30, // 3
	2, 6, 10, 18, 31, 2, 2, // 4
	31, 16, 16, 30, 1, 1, 30, // 5
	14, 16, 16, 30, 17, 17, 14, // 6
	31, 1, 2, 4, 8, 8, 8, // 7
	14, 17, 17, 14, 17, 17, 14, // 8
	14, 17, 17, 15, 1, 1, 14, // 9
]

const extended_rows = [
	u8(10), 0, 14, 1, 15, 17, 15, // ä
	10, 0, 14, 17, 17, 17, 14, // ö
	10, 0, 17, 17, 17, 19, 13, // ü
	10, 14, 17, 31, 17, 17, 17, // Ä
	10, 14, 17, 17, 17, 17, 14, // Ö
	10, 17, 17, 17, 17, 17, 14, // Ü
	14, 17, 17, 30, 17, 17, 30, // ß
	2, 4, 14, 17, 31, 16, 14, // é
	10, 5, 30, 17, 17, 17, 17, // ñ
	0, 14, 17, 16, 17, 14, 4, // ç
	4, 15, 20, 14, 5, 30, 4, // $
	7, 8, 30, 8, 30, 8, 7, // €
	6, 9, 8, 28, 8, 8, 31, // £
	17, 17, 10, 31, 4, 31, 4, // ¥
	14, 17, 23, 21, 23, 16, 14, // @
	12, 18, 20, 8, 21, 18, 13, // &
	14, 17, 1, 2, 4, 0, 4, // ?
	0, 4, 4, 0, 4, 4, 0, // :
	0, 4, 4, 0, 4, 4, 8, // ;
	16, 8, 8, 4, 2, 2, 1, // backslash
	2, 4, 8, 8, 8, 4, 2, // (
	8, 4, 2, 2, 2, 4, 8, // )
	14, 8, 8, 8, 8, 8, 14, // [
	14, 2, 2, 2, 2, 2, 14, // ]
	17, 18, 2, 4, 8, 9, 17, // %
	10, 31, 10, 10, 31, 10, 0, // #
	0, 21, 14, 31, 14, 21, 0, // *
	0, 0, 31, 0, 31, 0, 0, // =
	0, 0, 0, 0, 0, 0, 31, // _
	4, 10, 4, 0, 0, 0, 0, // °
	4, 4, 8, 0, 0, 0, 0, // apostrophe
	10, 10, 0, 0, 0, 0, 0, // quote
	4, 14, 21, 4, 4, 4, 4, // ↑
	4, 4, 4, 4, 21, 14, 4, // ↓
	0, 4, 8, 31, 8, 4, 0, // ←
	0, 4, 2, 31, 2, 4, 0, // →
]

// Unknown characters render as '?'; ASCII lowercase uses the existing uppercase
// shapes, while supported accented lowercase letters keep their own shapes.
pub fn code_for_rune(character rune) int {
	value := int(character)
	if value >= 65 && value <= 90 {
		return value - 64
	}
	if value >= 97 && value <= 122 {
		return value - 96
	}
	if value >= 48 && value <= 57 {
		return value - 48 + 27
	}
	return match value {
		32 { 0 } // space
		47 { 37 } // /
		43 { 38 } // +
		45 { 39 } // -
		46 { 40 } // .
		44 { 41 } // ,
		228 { 42 } // ä
		246 { 43 } // ö
		252 { 44 } // ü
		196 { 45 } // Ä
		214 { 46 } // Ö
		220 { 47 } // Ü
		223 { 48 } // ß
		233 { 49 } // é
		241 { 50 } // ñ
		231 { 51 } // ç
		36 { 52 } // $
		8364 { 53 } // €
		163 { 54 } // £
		165 { 55 } // ¥
		64 { 56 } // @
		38 { 57 } // &
		63 { 58 } // ?
		58 { 59 } // :
		59 { 60 } // ;
		92 { 61 } // backslash
		40 { 62 } // (
		41 { 63 } // )
		91 { 64 } // [
		93 { 65 } // ]
		37 { 66 } // %
		35 { 67 } // #
		42 { 68 } // *
		61 { 69 } // =
		95 { 70 } // _
		176 { 71 } // °
		39 { 72 } // apostrophe
		34 { 73 } // quote
		8593 { 74 } // ↑
		8595 { 75 } // ↓
		8592 { 76 } // ←
		8594 { 77 } // →
		else { 58 }
	}
}

pub fn encode(text string) []int {
	mut codes := []int{cap: text.len}
	for character in text.runes() {
		codes << code_for_rune(character)
	}
	return codes
}

pub fn bitmap(code int) []u8 {
	if code >= 1 && code <= 26 {
		start := (code - 1) * height
		return letter_rows[start..start + height].clone()
	}
	if code >= 27 && code <= 36 {
		start := (code - 27) * height
		return digit_rows[start..start + height].clone()
	}
	if code >= 42 && code <= 77 {
		start := (code - 42) * height
		return extended_rows[start..start + height].clone()
	}
	return match code {
		37 { [u8(1), 2, 4, 8, 16, 0, 0] } // /
		38 { [u8(0), 4, 4, 31, 4, 4, 0] } // +
		39 { [u8(0), 0, 0, 31, 0, 0, 0] } // -
		40 { [u8(0), 0, 0, 0, 0, 0, 4] } // .
		41 { [u8(0), 0, 0, 0, 0, 4, 8] } // ,
		else { [u8(0), 0, 0, 0, 0, 0, 0] }
	}
}

pub fn bitmap_for_rune(character rune) []u8 {
	return bitmap(code_for_rune(character))
}

pub fn pixel_on(code int, row int, column int) bool {
	if row < 0 || row >= height || column < 0 || column >= width {
		return false
	}
	return (bitmap(code)[row] & (u8(1) << u8(width - 1 - column))) != 0
}
