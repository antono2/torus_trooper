module font5x7

// The original 5×7 glyphs already have a fixed width. This separate variant
// gives each glyph an explicit 6×8 cell: five ink columns plus one empty
// column, and seven ink rows plus one empty row. It is not used by the game.
pub const mono_width = 6
pub const mono_height = 8

pub struct MonoLine {
pub:
	width  int
	height int
	// Row-major, one byte per pixel (0 or 1). The blank spacing is included.
	pixels []u8
}

// Bit 5 is the leftmost pixel; bit 0 is the guaranteed empty rightmost column.
pub fn mono_bitmap(code int) []u8 {
	mut rows := []u8{len: mono_height}
	glyph := bitmap(code)
	for row in 0 .. height {
		rows[row] = glyph[row] << 1
	}
	return rows
}

pub fn mono_bitmap_for_rune(character rune) []u8 {
	return mono_bitmap(code_for_rune(character))
}

pub fn mono_pixel_on(code int, row int, column int) bool {
	if row < 0 || row >= mono_height || column < 0 || column >= mono_width {
		return false
	}
	return (mono_bitmap(code)[row] & (u8(1) << u8(mono_width - 1 - column))) != 0
}

// Rasterize a single line of Unicode text into fixed-size monochrome cells.
pub fn mono_line(text string) MonoLine {
	codes := encode(text)
	line_width := codes.len * mono_width
	mut pixels := []u8{len: line_width * mono_height}
	for index, code in codes {
		rows := mono_bitmap(code)
		for row in 0 .. mono_height {
			for column in 0 .. mono_width {
				if (rows[row] & (u8(1) << u8(mono_width - 1 - column))) != 0 {
					pixels[row * line_width + index * mono_width + column] = 1
				}
			}
		}
	}
	return MonoLine{
		width:  line_width
		height: mono_height
		pixels: pixels
	}
}
