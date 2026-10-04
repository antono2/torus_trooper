module sim

// RGB components are normalized to 0..1; alpha and lighting are applied by the
// renderer. Names describe the hues, not CSS color values. Palette order is
// part of seeded level/ship generation, so keep indices stable for replays.
pub struct RgbColor {
pub:
	r f32
	g f32
	b f32
}

// Tunnel wire and panel entries at the same index form one level palette.
const wire_periwinkle = RgbColor{ r: 0.6, g: 0.7, b: 1 }
const wire_sea_green = RgbColor{ r: 0.4, g: 0.8, b: 0.6 }
const wire_dusty_rose = RgbColor{ r: 0.7, g: 0.5, b: 0.6 }
const wire_gray = RgbColor{ r: 0.6, g: 0.6, b: 0.6 }
const wire_teal = RgbColor{ r: 0.4, g: 0.7, b: 0.7 }
const wire_sage = RgbColor{ r: 0.6, g: 0.7, b: 0.5 }
const wire_violet = RgbColor{ r: 0.6, g: 0.4, b: 1 }

const panel_ice_blue = RgbColor{ r: 0.7, g: 0.9, b: 1 }
const panel_mint = RgbColor{ r: 0.6, g: 1, b: 0.8 }
const panel_peach = RgbColor{ r: 0.9, g: 0.7, b: 0.6 }
const panel_silver = RgbColor{ r: 0.8, g: 0.8, b: 0.8 }
const panel_aqua = RgbColor{ r: 0.5, g: 0.9, b: 0.9 }
const panel_lime = RgbColor{ r: 0.7, g: 0.9, b: 0.6 }
const panel_orchid = RgbColor{ r: 0.8, g: 0.5, b: 0.9 }

// Base hull colors; the ship shader adds contrasting trim and surface markings.
const hull_white = RgbColor{ r: 1, g: 1, b: 1 }
const hull_gray = RgbColor{ r: 0.5, g: 0.5, b: 0.5 }
const hull_red = RgbColor{ r: 0.95, g: 0.16, b: 0.12 }
const hull_green = RgbColor{ r: 0.18, g: 0.82, b: 0.28 }
const hull_blue = RgbColor{ r: 0.18, g: 0.4, b: 1 }
const hull_gold = RgbColor{ r: 0.95, g: 0.7, b: 0.12 }
const hull_magenta = RgbColor{ r: 0.85, g: 0.2, b: 0.9 }
const hull_cyan = RgbColor{ r: 0.08, g: 0.72, b: 0.95 }

// The tuning scene uses a fixed wire color instead of the level palette.
pub const calibration_ice_cyan = RgbColor{ r: 0.65, g: 0.95, b: 1.0 }

fn tunnel_line_palette(index int) RgbColor {
	return match index % 7 {
		0 { wire_periwinkle }
		1 { wire_sea_green }
		2 { wire_dusty_rose }
		3 { wire_gray }
		4 { wire_teal }
		5 { wire_sage }
		else { wire_violet }
	}
}

fn tunnel_poly_palette(index int) RgbColor {
	return match index % 7 {
		0 { panel_ice_blue }
		1 { panel_mint }
		2 { panel_peach }
		3 { panel_silver }
		4 { panel_aqua }
		5 { panel_lime }
		else { panel_orchid }
	}
}

fn ship_structure_color(index int) RgbColor {
	return match int_max(0, int_min(7, index)) {
		0 { hull_white }
		1 { hull_gray }
		2 { hull_red }
		3 { hull_green }
		4 { hull_blue }
		5 { hull_gold }
		6 { hull_magenta }
		else { hull_cyan }
	}
}
