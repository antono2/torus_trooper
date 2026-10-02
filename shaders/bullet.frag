#version 450

layout(location = 0) in vec2 local_position;
layout(location = 1) flat in float instance_kind;
layout(location = 2) flat in float instance_payload;
layout(location = 3) flat in float instance_selected;
layout(location = 0) out vec4 color;

layout(push_constant) uniform Display {
    layout(offset = 48) float brightness;
    layout(offset = 52) float luminosity;
    layout(offset = 64) float transition_fade;
} display;

const float particle_payload_scale = 0.000002;
const float particle_reflection_heading_offset = 10000.0;
const float enemy_shape_tier_stride = 0.125;
const float enemy_shape_code_multiplier = 2097152.0;
const uint enemy_damaged_code_offset = 100000u;
const int multiplier_large_label_offset = 128;
const float calibration_label_kind_base = 96.0;

const int calibration_label_starts[17] = int[](
	0, 6, 17, 26, 38, 49, 61, 71, 79, 94, 107, 117, 131, 143, 156, 173, 179
);
const int calibration_label_chars[179] = int[](
	15, 11, 0, 24, 4, 17, 15, 11, 0, 24, 4, 17, 26, 18, 7, 14, 19, 18,
	19, 0, 17, 26, 18, 7, 14, 19, 2, 7, 0, 17, 6, 4, 3, 26, 18, 7, 14,
	19, 4, 13, 4, 12, 24, 26, 18, 12, 0, 11, 11, 4, 13, 4, 12, 24, 26,
	12, 8, 3, 3, 11, 4, 4, 13, 4, 12, 24, 26, 1, 14, 18, 18, 1, 14, 18,
	18, 26, 1, 8, 19, 1, 20, 11, 11, 4, 19, 26, 19, 17, 8, 0, 13, 6, 11,
	4, 1, 20, 11, 11, 4, 19, 26, 18, 16, 20, 0, 17, 4, 1, 20, 11, 11, 4,
	19, 26, 1, 0, 17, 15, 0, 17, 19, 8, 2, 11, 4, 26, 18, 15, 0, 17, 10,
	15, 0, 17, 19, 8, 2, 11, 4, 26, 9, 4, 19, 15, 0, 17, 19, 8, 2, 11, 4,
	26, 18, 19, 0, 17, 15, 0, 17, 19, 8, 2, 11, 4, 26, 5, 17, 0, 6, 12, 4,
	13, 19, 19, 20, 13, 13, 4, 11
);
const int calibration_glyph_rows[189] = int[](
	14, 17, 17, 31, 17, 17, 17, // A
	30, 17, 17, 30, 17, 17, 30, // B
	15, 16, 16, 16, 16, 16, 15, // C
	30, 17, 17, 17, 17, 17, 30, // D
	31, 16, 16, 30, 16, 16, 31, // E
	31, 16, 16, 30, 16, 16, 16, // F
	15, 16, 16, 23, 17, 17, 15, // G
	17, 17, 17, 31, 17, 17, 17, // H
	14, 4, 4, 4, 4, 4, 14,       // I
	1, 1, 1, 1, 17, 17, 14,      // J
	17, 18, 20, 24, 20, 18, 17, // K
	16, 16, 16, 16, 16, 16, 31, // L
	17, 27, 21, 21, 17, 17, 17, // M
	17, 25, 21, 19, 17, 17, 17, // N
	14, 17, 17, 17, 17, 17, 14, // O
	30, 17, 17, 30, 16, 16, 16, // P
	14, 17, 17, 17, 21, 18, 13, // Q
	30, 17, 17, 30, 20, 18, 17, // R
	15, 16, 16, 14, 1, 1, 30,   // S
	31, 4, 4, 4, 4, 4, 4,        // T
	17, 17, 17, 17, 17, 17, 14, // U
	17, 17, 17, 17, 17, 10, 4,  // V
	17, 17, 17, 21, 21, 21, 10, // W
	17, 17, 10, 4, 10, 17, 17,  // X
	17, 17, 10, 4, 4, 4, 4,     // Y
	31, 1, 2, 4, 8, 16, 31,     // Z
	0, 0, 0, 0, 0, 0, 31        // underscore separator
);

bool calibration_label_glyph(vec2 point, int label) {
	vec2 uv = point * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x >= 1.0 || uv.y < 0.0 || uv.y >= 1.0)
		return false;
	int start = calibration_label_starts[label];
	int length = calibration_label_starts[label + 1] - start;
	float character_position = uv.x * float(length);
	int character = int(floor(character_position));
	int column = int(floor(fract(character_position) * 6.0));
	int row = int(floor(uv.y * 7.0));
	if (character < 0 || character >= length || column >= 5 || row < 0 || row >= 7)
		return false;
	int glyph = calibration_label_chars[start + character];
	return (calibration_glyph_rows[glyph * 7 + row] & (1 << (4 - column))) != 0;
}

uint hash_u32(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

float shape_value(uint seed, uint stream) {
    return float(hash_u32(seed + stream * 0x9e3779b9u) & 0xffffu) / 65535.0;
}

bool ship_shaft(vec2 point, float x_offset, float half_width, float length,
                float y_offset) {
    vec2 q = point - vec2(x_offset, y_offset);
    float half_length = length * 0.5;
    if (q.y < -half_length || q.y > half_length) return false;
    float nose_taper = clamp((half_length - q.y) / (length * 0.24), 0.0, 1.0);
    float tail_taper = clamp((q.y + half_length) / (length * 0.10), 0.0, 1.0);
    float envelope = half_width * min(nose_taper, tail_taper);
    return abs(q.x) < max(0.018, envelope);
}

bool swept_wing(vec2 point, float root, float span, float anchor, float sweep,
                float thickness) {
    float x = abs(point.x);
    if (x < root || x > span) return false;
    float progress = (x - root) / max(0.001, span - root);
    float center = anchor - sweep * progress;
    return abs(point.y - center) < thickness * (1.0 - progress * 0.68);
}

// ShipShape(1) in the original MT19937 generator selects two shafts and
// triangular wings. Keep that player-only result fixed instead of hashing it
// like the per-zone enemy shapes.
bool player_ship(vec2 point) {
    bool shafts = ship_shaft(point, -0.22, 0.105, 1.37, -0.04)
        || ship_shaft(point, 0.22, 0.105, 1.37, -0.04);
    bool wings = swept_wing(point, 0.09, 0.86, 0.13, 0.31, 0.17);
    bool tail_bridge = point.y > -0.58 && point.y < -0.43 && abs(point.x) < 0.34;
    return shafts || wings || tail_bridge;
}

// The original BitShape is four long axial bars plus four wider bars rotated
// by 45 degrees. Its translucent faces read as a small radial cage in 2D.
bool boss_bit(vec2 point) {
    vec2 diagonal = vec2(point.x + point.y, point.y - point.x) * 0.70710678;
    bool axial_bars = ((abs(point.x) < 0.10 && abs(point.y) < 0.82)
        || (abs(point.y) < 0.10 && abs(point.x) < 0.82)) && length(point) > 0.20;
    bool diagonal_bars = ((abs(diagonal.x) < 0.105 && abs(diagonal.y) < 0.94)
        || (abs(diagonal.y) < 0.105 && abs(diagonal.x) < 0.94))
        && length(diagonal) > 0.48;
    bool hub = length(point) > 0.20 && length(point) < 0.34;
    return axial_bars || diagonal_bars || hub;
}

float radial_blade_field(vec2 point, float blade_count) {
    float radius = length(point);
    float turns = atan(point.y, point.x) / 6.28318530718;
    float sector_distance = abs(fract(turns * blade_count + 0.5) - 0.5) * 2.0;
    float half_width = mix(0.34, 0.075, smoothstep(0.12, 0.92, radius));
    return max(radius - 0.92, min(radius - 0.15, sector_distance - half_width));
}

// The source ChargeShotShape is eight triangles whose vertices sit at radial
// distances 0.1, 0.5, and 1.0 and local heights 0.2, 0.5, and -0.7. The height
// term below skews each face in projection and drives its bright-to-dark shade.
float charged_weapon_field(vec2 point, out float surface_light) {
    float field = length(point) - 0.12;
    surface_light = field < 0.0 ? 1.0 : 0.0;
	for (int blade = 0; blade < 8; ++blade) {
		float angle = float(blade) * 0.78539816339;
		vec2 direction = vec2(sin(angle), cos(angle));
		vec2 tangent_axis = vec2(direction.y, -direction.x);
		float radial = dot(point, direction);
		float height = radial < 0.5
			? mix(0.2, 0.5, clamp((radial - 0.1) / 0.4, 0.0, 1.0))
			: mix(0.5, -0.7, clamp((radial - 0.5) / 0.5, 0.0, 1.0));
		float tangent = dot(point, tangent_axis) + height * 0.055;
		float half_width = radial < 0.5
			? mix(0.018, 0.13, clamp((radial - 0.1) / 0.4, 0.0, 1.0))
			: mix(0.13, 0.025, clamp((radial - 0.5) / 0.5, 0.0, 1.0));
        float blade_field = max(abs(tangent) - half_width,
                                max(0.08 - radial, radial - 1.0));
        field = min(field, blade_field);
        if (blade_field < 0.0) {
			float face_light = radial < 0.5 ? 1.0
				: mix(1.0, 0.2, (radial - 0.5) * 2.0);
			surface_light = max(surface_light, face_light);
		}
	}
	return field;
}

bool enemy_ship(vec2 point, uint enemy_tier, uint seed) {
    float length_variation = shape_value(seed, 1u);
    float spacing_variation = shape_value(seed, 2u);
    float wing_variation = shape_value(seed, 3u);
    bool alternate = shape_value(seed, 4u) > 0.5;
    bool visible = false;
    if (enemy_tier == 0u) {
        float length = mix(1.18, 1.55, length_variation);
        float spacing = mix(0.17, 0.27, spacing_variation);
        if (alternate) {
            visible = ship_shaft(point, -spacing, 0.105, length * 0.88, -0.05)
                || ship_shaft(point, spacing, 0.105, length * 0.88, -0.05);
        } else {
            visible = ship_shaft(point, 0.0, 0.15, length, 0.0);
        }
        visible = visible || swept_wing(point, 0.05, mix(0.68, 0.90, wing_variation),
            0.10, mix(0.22, 0.48, wing_variation), 0.17);
    } else if (enemy_tier == 1u) {
        float spacing = mix(0.29, 0.40, spacing_variation);
        float length = mix(1.20, 1.68, length_variation);
        if (alternate) {
            visible = ship_shaft(point, -spacing * 0.45, 0.09, length * 0.68, -0.17)
                || ship_shaft(point, spacing * 0.45, 0.09, length * 0.68, -0.17)
                || ship_shaft(point, -spacing, 0.105, length, 0.02)
                || ship_shaft(point, spacing, 0.105, length, 0.02);
        } else {
            visible = ship_shaft(point, 0.0, 0.12, length, 0.0)
                || ship_shaft(point, -spacing, 0.105, length * 0.80, -0.10)
                || ship_shaft(point, spacing, 0.105, length * 0.80, -0.10);
        }
        visible = visible || swept_wing(point, 0.10, mix(0.76, 0.96, wing_variation),
            0.13, mix(0.20, 0.44, wing_variation), 0.15);
    } else {
        float spacing = mix(0.19, 0.25, spacing_variation);
        float length = mix(1.30, 1.78, length_variation);
        if (!alternate) {
            visible = ship_shaft(point, 0.0, 0.095, length, 0.02);
        }
        visible = visible || ship_shaft(point, -spacing, 0.08, length * 0.72, -0.18)
            || ship_shaft(point, spacing, 0.08, length * 0.72, -0.18)
            || ship_shaft(point, -spacing * 2.25, 0.09, length * 0.90, -0.04)
            || ship_shaft(point, spacing * 2.25, 0.09, length * 0.90, -0.04);
        if (alternate) {
            visible = visible
                || ship_shaft(point, -spacing * 0.62, 0.07, length * 0.58, -0.27)
                || ship_shaft(point, spacing * 0.62, 0.07, length * 0.58, -0.27);
        }
        visible = visible || swept_wing(point, 0.08, mix(0.82, 0.98, wing_variation),
            0.17, mix(0.22, 0.48, wing_variation), 0.14);
    }
    return visible;
}

const int popup_digit_rows[70] = int[](
    14, 17, 19, 21, 25, 17, 14,
    4, 12, 4, 4, 4, 4, 14,
    14, 17, 1, 2, 4, 8, 31,
    30, 1, 1, 14, 1, 1, 30,
    2, 6, 10, 18, 31, 2, 2,
    31, 16, 16, 30, 1, 1, 30,
    14, 16, 16, 30, 17, 17, 14,
    31, 1, 2, 4, 8, 8, 8,
    14, 17, 17, 14, 17, 17, 14,
    14, 17, 17, 15, 1, 1, 14
);

bool multiplier_glyph(vec2 point, int multiplier) {
    int digit_count = multiplier >= 100 ? 3 : (multiplier >= 10 ? 2 : 1);
    int character_count = digit_count + 1;
    vec2 uv = point * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x >= 1.0 || uv.y < 0.0 || uv.y >= 1.0)
        return false;
    float character_position = uv.x * float(character_count);
    int character = int(floor(character_position));
    int column = int(floor(fract(character_position) * 6.0));
    // Vulkan's positive-height viewport maps local -Y to the top of the
    // screen. Read the bitmap rows in that same direction; reversing uv.y made
    // multiplier labels appear vertically mirrored.
    int row = int(floor(uv.y * 7.0));
    if (column >= 5 || row < 0 || row >= 7) return false;
    int row_mask;
    if (character == 0) {
        const int x_rows[7] = int[](17, 17, 10, 4, 10, 17, 17);
        row_mask = x_rows[row];
    } else {
        int digit;
        if (digit_count == 3)
            digit = character == 1 ? multiplier / 100 :
                    (character == 2 ? (multiplier / 10) % 10 : multiplier % 10);
        else if (digit_count == 2)
            digit = character == 1 ? multiplier / 10 : multiplier % 10;
        else
            digit = multiplier;
        row_mask = popup_digit_rows[digit * 7 + row];
    }
    return (row_mask & (1 << (4 - column))) != 0;
}

void main() {
	vec2 p = local_position;
	if (instance_kind >= calibration_label_kind_base
		&& instance_kind < calibration_label_kind_base + 16.0) {
		int label = clamp(int(round(instance_payload)), 0, 15);
		bool core = calibration_label_glyph(p, label);
		vec2 step_size = vec2(0.012, 0.08);
		bool shadow = calibration_label_glyph(p + vec2(step_size.x, 0.0), label)
			|| calibration_label_glyph(p + vec2(0.0, step_size.y), label);
		if (!core && !shadow) discard;
		vec3 label_color = core ? vec3(0.80, 0.96, 1.0) : vec3(0.01, 0.02, 0.04);
		color = vec4(label_color * (1.0 - display.transition_fade), 1.0);
		return;
	}
	if (instance_kind >= 19.5 && instance_kind < 30.0) {
		int popup_code = int(floor(instance_payload));
		int multiplier = clamp(popup_code - (popup_code >= multiplier_large_label_offset
			? multiplier_large_label_offset : 0), 2, 100);
		bool core = multiplier_glyph(p, multiplier);
		int character_count = multiplier >= 100 ? 4 : (multiplier >= 10 ? 3 : 2);
		vec2 outline_step = vec2(2.0 / (float(character_count) * 6.0), 2.0 / 7.0) * 0.18;
		bool outline = multiplier_glyph(p + vec2(outline_step.x, 0.0), multiplier)
		            || multiplier_glyph(p - vec2(outline_step.x, 0.0), multiplier)
		            || multiplier_glyph(p + vec2(0.0, outline_step.y), multiplier)
		            || multiplier_glyph(p - vec2(0.0, outline_step.y), multiplier);
		if (!core && !outline) discard;
		float alpha = core ? 1.0 : clamp(fract(instance_payload), 0.0, 0.8);
		vec3 popup_color = vec3(display.brightness + display.luminosity * 0.45);
		color = vec4(popup_color * (1.0 - display.transition_fade), alpha);
		return;
	}
    float radius = length(p);
    float glow = 1.0 - smoothstep(0.1, 1.0, radius);
    vec3 selected;
    bool visible = false;
    float shape_alpha = 1.0;
	float particle_luminosity = 1.0;
	float output_alpha = 1.0;
	bool reflected_particle = instance_kind >= 6.0 && instance_kind < 7.0
		&& instance_payload > particle_reflection_heading_offset * 0.5;

    if (instance_kind < 0.5) {
        visible = radius < 0.82;
        selected = vec3(1.0, 0.30 + glow * 0.62, 0.08);
    } else if (instance_kind < 1.5) {
        visible = player_ship(p);
        selected = vec3(0.42, 0.86 + glow * 0.14, 0.88);
    } else if (instance_kind < 2.5) {
        float field = radial_blade_field(p, 4.0);
        float aa = max(fwidth(field), 0.002);
        shape_alpha = 1.0 - smoothstep(-aa, aa, field);
        visible = shape_alpha > 0.0;
        float core = 1.0 - smoothstep(-0.14 - aa, -0.14 + aa, field);
        vec3 hot = instance_kind >= 2.2 ? vec3(1.0, 0.94, 0.42)
                                       : vec3(0.62, 1.0, 0.86);
        selected = mix(vec3(0.015, 0.035, 0.065), hot, core);
    } else if (instance_kind < 3.5) {
        uint enemy_tier = uint(clamp(floor((instance_kind - 3.0) /
                                           enemy_shape_tier_stride + 0.001),
                                      0.0, 2.0));
        float tier_base = 3.0 + float(enemy_tier) * enemy_shape_tier_stride;
        uint packed_shape = uint(round((instance_kind - tier_base) *
                                       enemy_shape_code_multiplier));
        bool enemy_damaged = packed_shape >= enemy_damaged_code_offset;
        uint shape_seed = packed_shape % enemy_damaged_code_offset;
        visible = enemy_ship(p, enemy_tier, shape_seed);
        float tint = shape_value(shape_seed, 5u);
        selected = enemy_damaged ? vec3(1.0)
            : mix(vec3(0.72, 0.015, 0.16), vec3(0.12, 0.025, 0.68), tint * 0.42);
    } else if (instance_kind < 4.9) {
        visible = boss_bit(p);
        selected = radius > 0.68 ? vec3(0.10, 0.01, 0.18)
                                 : vec3(1.0, 0.30 + glow * 0.20, 0.02);
	} else if (instance_kind < 5.5) {
		float surface_light;
        float field = charged_weapon_field(p, surface_light);
        float aa = max(fwidth(field), 0.002);
        shape_alpha = 1.0 - smoothstep(-aa, aa, field);
        visible = shape_alpha > 0.0;
        float core = 1.0 - smoothstep(-0.020 - aa, -0.020 + aa, field);
        selected = mix(vec3(0.015, 0.035, 0.065),
                       vec3(0.62, 1.0, 0.86) * mix(0.65, 1.0, surface_light), core);
	} else if (instance_kind > 62.5) {
		visible = abs(radius - 0.94) < 0.035;
		selected = vec3(0.55, 0.95, 1.0);
	} else if (instance_kind >= 7.0) {
		int bullet_shape = int(floor(instance_kind - 7.0 + 0.01));
		bool wire = (bullet_shape & 1) != 0;
		int family = bullet_shape / 2;
		float field;
		if (family == 0) {
			float width = clamp((p.y + 0.9) * 0.55, 0.0, 0.9);
			field = max(abs(p.x) - width, max(-p.y - 0.9, p.y - 0.72));
		} else if (family == 1) {
			field = max(abs(p.x), abs(p.y)) - 0.78;
		} else {
			field = max(abs(p.x) - 0.24, abs(p.y) - 0.90);
		}
		// Hostile projectiles use a dark silhouette around a hot core. Both
		// halves remain legible against every light panel palette as well as the
		// dark wire/open-course background.
		float edge_distance = abs(field);
        float silhouette = wire ? edge_distance - 0.16 : field - 0.10;
        float aa = max(fwidth(silhouette), 0.002);
        shape_alpha = 1.0 - smoothstep(-aa, aa, silhouette);
        visible = shape_alpha > 0.0;
        float core_distance = wire ? edge_distance - 0.065 : field + 0.12;
        float core = 1.0 - smoothstep(-aa, aa, core_distance);
        selected = mix(vec3(0.09, 0.005, 0.16),
                       vec3(1.0, 0.20 + glow * 0.24, 0.015), core);
	} else {
		float particle_code = instance_kind - 6.0;
		float particle_variant = floor(particle_code / 0.25 + 0.001);
		float particle_detail = particle_code - particle_variant * 0.25;
		int particle_payload = int(round(particle_detail / particle_payload_scale));
		float particle_tier = float(particle_payload / 32768);
		particle_luminosity = float(particle_payload % 16) / 15.0;
		if (particle_variant < 0.5) {
			float width = mix(0.30, 0.055, clamp((p.y + 0.92) / 1.55, 0.0, 1.0));
			visible = p.y > -0.92 && p.y < 0.68 && abs(p.x) < width;
			output_alpha = 0.5 * clamp((0.68 - p.y) / 1.60, 0.0, 1.0);
			selected = particle_tier >= 0.5 ? vec3(0.60, 1.0, 0.80)
			                                     : vec3(1.0, 0.50 + glow * 0.48, 0.04);
		} else if (particle_variant < 1.5) {
			float width = mix(0.34, 0.045, clamp((p.y + 0.96) / 1.76, 0.0, 1.0));
			visible = p.y > -0.96 && p.y < 0.80 && abs(p.x) < width;
			// The nozzle-facing tip is bright and the widening tail fades, matching
			// the source spark whose previous position is the opaque endpoint.
			output_alpha = 0.5 * clamp((p.y + 0.96) / 1.76, 0.0, 1.0);
			selected = particle_tier >= 0.5 ? vec3(0.30, 0.40, 1.0)
			                                     : vec3(0.90, 0.50 + glow * 0.20, 1.0);
		} else if (particle_variant < 2.5) {
			visible = abs(p.x) < 0.10 && p.y > -0.96 && p.y < 0.88;
			output_alpha = mix(1.0, 0.2, clamp((p.y + 0.96) / 1.84, 0.0, 1.0));
			selected = vec3(0.75 + glow * 0.25, 0.82, 1.0);
		} else {
			float edge = max(abs(p.x), abs(p.y));
			visible = edge < 1.0;
			output_alpha = edge > 0.78 ? 0.5 : 0.2;
			selected = edge > 0.78 ? vec3(1.0, 0.52, 0.30)
			                       : vec3(0.62 + glow * 0.20, 0.16, 0.10);
		}
    }

	bool tunnel_visual = instance_kind > 62.5;
	bool calibration_mesh_proxy = instance_selected > 1.5;
	bool selection_border = (calibration_mesh_proxy ? instance_selected > 2.5
		: instance_selected > 0.5)
		&& (tunnel_visual ? abs(radius - 0.99) < 0.018
		: max(abs(p.x), abs(p.y)) > 0.84
		&& max(abs(p.x), abs(p.y)) < 0.98);
	if (calibration_mesh_proxy && !selection_border) discard;
	if (!visible && !selection_border) discard;
	if (selection_border) {
		color = vec4(vec3(0.30, 1.0, 0.92) * (display.brightness + display.luminosity),
			1.0);
		return;
	}
	vec3 luminous_color = selected * (display.brightness + glow * display.luminosity * 0.65)
		* mix(0.35, 1.0, particle_luminosity);
	if (reflected_particle) output_alpha *= 0.4;
	color = vec4(luminous_color * (1.0 - display.transition_fade), output_alpha * shape_alpha);
}
