# 5×7 bitmap font

`font5x7` exposes the game's 5×7 glyphs as seven-byte bitmaps. The low five
bits of each byte are one row, with bit 4 at the left edge.

From a V program in this repository:

```v
import font5x7

codes := font5x7.encode('Grüße, 20 € →')
for code in codes {
    rows := font5x7.bitmap(code)
    // Draw set bits in each of the seven rows.
    println(rows)
}
```

`code_for_rune`, `bitmap_for_rune`, and `pixel_on` are available for individual
characters. Codes 0–41 preserve the game's existing HUD layout: space, A–Z,
0–9, `/`, `+`, `-`, `.`, and `,`. Codes 42–77 add `ä ö ü Ä Ö Ü ß é ñ ç`,
`$ € £ ¥ @ & ? : ; \\ ( ) [ ] % # * = _ ° ' "`, and four arrow symbols
`↑ ↓ ← →`. ASCII lowercase uses uppercase glyphs; unsupported Unicode is
shown as `?`. Precomposed accented characters are supported; combining marks
are not composed automatically.

The same bitmap rows are available in `shaders/hud.vert` for GPU drawing. Its
character codes are deliberately stable, and the font test checks that the V
and GLSL copies agree.

## Mono cell variant

The original glyphs are already fixed-width. For applications that need an
explicit monospaced raster, `mono_bitmap(code)` returns an 8-byte, 6×8 cell
with one empty column and one empty row for spacing. `mono_line(text)` returns
row-major 0/1 pixels for a single line at exactly six pixels per Unicode
character. `mono_bitmap_for_rune` and `mono_pixel_on` cover individual glyphs.
This variant is not used by Torus Trooper's HUD yet.
