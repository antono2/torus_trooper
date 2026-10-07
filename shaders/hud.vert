// Builds HUD glyph and overlay geometry from the shared packed HUD state.
#version 450
#extension GL_GOOGLE_include_directive : require
#include "palette.glsl"
#include "hud_state.h"

layout(push_constant) uniform Frame {
    float time;
    float aspect;
    float view_angle;
    int score;
    int remaining_time_ms;
    int hits;
    int zone;
    int state;
    layout(offset = 32) uint text0;
    layout(offset = 36) uint text1;
    layout(offset = 40) uint text2;
    layout(offset = 44) uint text3;
    layout(offset = 48) uint text4;
    layout(offset = 52) uint text5;
    layout(offset = 64) uint text8;
    layout(offset = 56) int title_normal_best_levels;
    layout(offset = 60) int title_hard_best_levels;
    layout(offset = 68) int speed;
    layout(offset = 72) int rank;
    layout(offset = 76) int rank_remaining;
    layout(offset = 80) int title_extreme_best_levels;
    layout(offset = 84) int near_fade_percent;
    layout(offset = 88) int rear_track_blend_percent;
    // Title-only packed panel (low ten bits) and wire (next ten bits) limits.
    layout(offset = 96) int track_draw_distance;
    layout(offset = 112) int next_extend_score;
    layout(offset = 116) int time_change_ticks;
    layout(offset = 120) int time_change_seconds;
    layout(offset = 108) float rotation;
    layout(offset = 124) int near_blur_percent;
} frame;

layout(location = 0) out vec3 glyph_color;
layout(location = 1) flat out float ignore_transition;
layout(location = 2) flat out float glyph_alpha;

const int title_digit_count = 66;
const int digit_vertex_count = 42 * title_digit_count;
const int title_major_segments = 32;
const int title_minor_segments = 16;
const int title_mask_offset = 0;
const int title_mask_vertex_count = title_major_segments * 6 +
                                    title_major_segments * title_minor_segments * 6 + 6;
const int digit_vertex_offset = title_mask_offset + title_mask_vertex_count;
const int title_torus_offset = digit_vertex_offset + digit_vertex_count;
const int title_torus_vertex_count = title_major_segments * title_minor_segments * 2 * 6;
const int title_wordmark_offset = title_torus_offset + title_torus_vertex_count;
const int title_wordmark_characters = 13;
const int title_wordmark_vertex_count = title_wordmark_characters * 7 * 5 * 6;
const int title_grade_ring_offset = title_wordmark_offset + title_wordmark_vertex_count;
const int title_grade_ring_count = 3;
const int title_grade_ring_segments = 64;
const int title_grade_label_offset = title_grade_ring_offset +
                                     title_grade_ring_count * title_grade_ring_segments * 6;
const int title_grade_label_character_count = 83;
const int title_grade_label_vertex_count = title_grade_label_character_count * 7 * 5 * 6;
const int gameplay_overlay_offset = title_grade_label_offset + title_grade_label_vertex_count;
const int gameplay_overlay_characters = 9;
const int gameplay_overlay_vertex_count = gameplay_overlay_characters * 7 * 5 * 6;
const int next_extend_offset = gameplay_overlay_offset + gameplay_overlay_vertex_count;
const int next_extend_digit_count = 7;
const int next_extend_vertex_count = next_extend_digit_count * 42;
const int time_change_offset = next_extend_offset + next_extend_vertex_count;
const int time_change_characters = 8;
const int gameplay_label_offset = time_change_offset + time_change_characters * 7 * 5 * 6;
const int gameplay_label_character_count = 46;
const int gameplay_label_vertex_count = gameplay_label_character_count * 7 * 5 * 6;
const int fps_offset = gameplay_label_offset + gameplay_label_vertex_count;
const int fps_character_count = 7;
const int fps_vertex_count = fps_character_count * 7 * 5 * 6;
const int help_offset = fps_offset + fps_vertex_count;
const int help_columns = 29;
const int help_lines = 23;
const int help_character_count = help_columns * help_lines;
const int help_source_lines = 11;
const int help_source_character_count = help_columns * help_source_lines;
const int help_diagram_vertex_count = 4 * 6;
const int help_text_offset = help_offset + help_diagram_vertex_count;
const int help_vertex_count = help_diagram_vertex_count + help_character_count * 7 * 5 * 6;
const int menu_selection_offset = help_offset + help_vertex_count;
const int menu_selection_vertex_count = 6 * 6;
const int digit_masks[11] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111, 64);
// One seven-row, five-bit bitmap per glyph. GLSL stores the row masks as ints;
// character codes 1..26 select A..Z and 27..36 select 0..9. Text is stored
// separately, so adding a word never duplicates its pixel rows.
const int character_digit_rows[70] = int[](
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
const int character_letter_rows[182] = int[](
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
    31, 1, 2, 4, 8, 16, 31      // Z
);
// Codes 42..77 extend the original HUD alphabet without changing old text.
// Keep these rows in sync with font5x7/font.v for Unicode text reuse.
const int character_extended_rows[252] = int[](
    10, 0, 14, 1, 15, 17, 15, // ä
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
    0, 4, 2, 31, 2, 4, 0 // →
);
const int help_characters[957] = int[](
    7, 15, 1, 12, 0, 28, 37, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    18, 1, 3, 5, 0, 20, 8, 18, 15, 21, 7, 8, 0, 20, 8, 5, 0, 20, 15, 18, 21, 19, 0, 0, 0, 0, 0, 0, 0,
    4, 5, 19, 20, 18, 15, 25, 0, 5, 14, 5, 13, 9, 5, 19, 0, 20, 15, 0, 19, 3, 15, 18, 5, 0, 0, 0, 0, 0,
    19, 3, 15, 18, 5, 0, 5, 24, 20, 5, 14, 4, 19, 0, 20, 9, 13, 5, 0, 2, 25, 0, 28, 32, 0, 0, 0, 0, 0,
    18, 5, 1, 3, 8, 0, 5, 1, 3, 8, 0, 2, 15, 19, 19, 0, 2, 5, 6, 15, 18, 5, 0, 0, 0, 0, 0, 0, 0,
    20, 9, 13, 5, 0, 18, 21, 14, 19, 0, 15, 21, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    3, 8, 1, 18, 7, 5, 0, 19, 8, 15, 20, 0, 3, 12, 5, 1, 18, 19, 0, 6, 9, 18, 5, 0, 0, 0, 0, 0, 0,
    1, 14, 4, 0, 16, 9, 5, 18, 3, 5, 19, 0, 5, 14, 5, 13, 9, 5, 19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    12, 5, 6, 20, 40, 0, 18, 9, 7, 8, 20, 0, 39, 0, 3, 8, 1, 14, 7, 5, 0, 16, 1, 7, 5, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    8, 21, 4, 0, 12, 1, 2, 5, 12, 19, 0, 29, 37, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    19, 3, 15, 18, 5, 0, 39, 0, 20, 15, 20, 1, 12, 0, 16, 15, 9, 14, 20, 19, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    14, 5, 24, 20, 0, 16, 12, 21, 19, 0, 28, 32, 0, 39, 0, 19, 3, 15, 18, 5, 0, 20, 1, 18, 7, 5, 20, 0, 0,
    20, 9, 13, 5, 0, 39, 0, 18, 5, 13, 1, 9, 14, 9, 14, 7, 0, 18, 21, 14, 0, 20, 9, 13, 5, 0, 0, 0, 0,
    12, 5, 22, 5, 12, 0, 39, 0, 3, 21, 18, 18, 5, 14, 20, 0, 12, 5, 22, 5, 12, 0, 0, 0, 0, 0, 0, 0, 0,
    19, 20, 1, 7, 5, 0, 16, 18, 15, 7, 18, 5, 19, 19, 0, 39, 0, 9, 14, 0, 12, 5, 22, 5, 12, 0, 0, 0, 0,
    2, 15, 19, 19, 0, 4, 9, 19, 20, 1, 14, 3, 5, 0, 39, 0, 18, 5, 13, 1, 9, 14, 9, 14, 7, 0, 0, 0, 0,
    19, 16, 5, 5, 4, 0, 39, 0, 11, 9, 12, 15, 13, 5, 20, 5, 18, 19, 0, 16, 5, 18, 0, 8, 15, 21, 18, 0, 0,
    8, 9, 20, 19, 0, 39, 0, 19, 8, 9, 16, 0, 4, 5, 19, 20, 18, 21, 3, 20, 9, 15, 14, 19, 0, 0, 0, 0, 0,
    12, 5, 6, 20, 40, 0, 18, 9, 7, 8, 20, 0, 39, 0, 3, 8, 1, 14, 7, 5, 0, 16, 1, 7, 5, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    7, 1, 13, 5, 0, 8, 15, 20, 11, 5, 25, 19, 0, 30, 37, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 18, 18, 15, 23, 19, 40, 0, 23, 40, 0, 1, 40, 0, 19, 40, 0, 4, 0, 39, 0, 13, 15, 22, 5, 0, 0, 0, 0,
    26, 40, 0, 19, 16, 1, 3, 5, 40, 0, 4, 15, 20, 40, 0, 3, 20, 18, 12, 0, 39, 0, 6, 9, 18, 5, 0, 0, 0,
    24, 40, 0, 19, 8, 9, 6, 20, 40, 0, 1, 12, 20, 40, 0, 19, 12, 1, 19, 8, 0, 39, 0, 3, 8, 1, 18, 7, 5,
    16, 0, 39, 0, 16, 1, 21, 19, 5, 41, 0, 6, 0, 39, 0, 6, 16, 19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    16, 12, 21, 19, 40, 0, 13, 9, 14, 21, 19, 0, 39, 0, 22, 15, 12, 21, 13, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    6, 28, 28, 0, 39, 0, 2, 15, 18, 4, 5, 18, 12, 5, 19, 19, 0, 6, 21, 12, 12, 19, 3, 18, 5, 5, 14, 0, 0,
    21, 16, 40, 0, 4, 15, 23, 14, 0, 39, 0, 19, 5, 12, 5, 3, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    12, 5, 6, 20, 40, 0, 18, 9, 7, 8, 20, 0, 39, 0, 3, 8, 1, 14, 7, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    5, 19, 3, 0, 39, 0, 2, 1, 3, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    18, 5, 2, 9, 14, 4, 0, 11, 5, 25, 19, 0, 9, 14, 0, 15, 16, 20, 9, 15, 14, 19, 41, 9, 14, 9, 0, 0, 0
);
// SCORE, TIME, LEVEL, HITS, KM/H, STAGE PROG, BOSS DIST, NEXT +15.
const int gameplay_label_codes[46] = int[](
    19, 3, 15, 18, 5, 20, 9, 13, 5, 12, 5, 22, 5, 12, 8, 9,
    20, 19, 11, 13, 37, 8, 19, 20, 1, 7, 5, 16, 18, 15, 7, 2,
    15, 19, 19, 4, 9, 19, 20, 14, 5, 24, 20, 38, 28, 32
);
const int fps_label_codes[4] = int[](6, 16, 19, 0);
const vec2 corners[6] = vec2[](
    vec2(-1, -1), vec2(1, -1), vec2(1, 1),
    vec2(-1, -1), vec2(1, 1), vec2(-1, 1)
);
const int title_wordmark_codes[13] = int[](
    20, 15, 18, 21, 19, 0, 20, 18, 15, 15, 16, 5, 18
);
const int game_over_codes[9] = int[](7, 1, 13, 5, 0, 15, 22, 5, 18);
const int paused_codes[9] = int[](16, 1, 21, 19, 5, 4, 0, 0, 0);

int character_glyph_row(int code, int row);

int decimal_digit(int value, int place) {
    int divisor = 1;
    for (int i = 0; i < place; ++i) divisor *= 10;
    return (value / divisor) % 10;
}

// Preserve the 16:9 text width on narrower windows. Without this scale the
// aspect correction makes labels grow horizontally into their values.
float responsive_text_scale() {
    return clamp(frame.aspect / (16.0 / 9.0), 0.65, 1.0);
}

float gameplay_label_pixel_height() {
    return 0.0075 * responsive_text_scale();
}

float gameplay_label_pixel_width() {
    return gameplay_label_pixel_height() / frame.aspect;
}

// Use whole framebuffer pixels for the dot pitch and face. Fractional
// spacing otherwise makes alternate columns look wider under antialiasing.
float font_pixel_height(float desired) {
    float height = max(uintBitsToFloat(frame.text5), 1.0);
    return max(2.0, round(desired * height * 0.5)) * 2.0 / height;
}

vec2 font_dot_position(vec2 cell, float pitch, vec2 corner) {
    float height = max(uintBitsToFloat(frame.text5), 1.0);
    vec2 extent = vec2(height * frame.aspect, height);
    float step_pixels = round(pitch * height * 0.5);
    float face_pixels = max(1.0, round(step_pixels * 0.68));
    vec2 origin = round((cell * 0.5 + 0.5) * extent)
        + floor((step_pixels - face_pixels) * 0.5);
    vec2 unit_corner = (corner - 0.16) / 0.68;
    return (origin + unit_corner * face_pixels) * 2.0 / extent - 1.0;
}

float gameplay_digit_spacing() {
    return 0.052 * responsive_text_scale() / frame.aspect;
}

float gameplay_digit_outer_half_width() {
    return 0.036 * responsive_text_scale() / frame.aspect;
}

float gameplay_digit_outer_half_height() {
    return 0.0365 * responsive_text_scale();
}

float next_extend_digit_outer_half_height() {
    return 0.0287 * responsive_text_scale();
}

float gameplay_label_width(int character_count) {
    return float(character_count * 6 - 1) * gameplay_label_pixel_width();
}

float gameplay_column_gap() {
    return 4.0 * gameplay_label_pixel_width();
}

float gameplay_value_width(int digit_count) {
    return float(digit_count - 1) * gameplay_digit_spacing()
         + 2.0 * gameplay_digit_outer_half_width();
}

bool gameplay_layout_stacks() {
    float quarter_width = 2.0 / 4.0;
    float field_padding = 4.0 * gameplay_label_pixel_width();
    float available_width = quarter_width - field_padding;
    float widest_bottom_pair = gameplay_label_width(9) + gameplay_column_gap()
                              + gameplay_value_width(3);
    return widest_bottom_pair > available_width;
}

float gameplay_stacked_value_anchor(float label_x, int digit_count) {
    return label_x + gameplay_digit_outer_half_width()
         + float(digit_count - 1) * gameplay_digit_spacing();
}

float gameplay_right_label_x() {
    float screen_edge = 1.0 - 2.0 * gameplay_digit_outer_half_width();
    float value_width = float(next_extend_digit_count - 1) * gameplay_digit_spacing()
                      + 2.0 * gameplay_digit_outer_half_width();
    return screen_edge - value_width - gameplay_column_gap()
         - gameplay_label_width(8);
}

float gameplay_row_value_anchor(int label_characters) {
    return gameplay_right_label_x() + gameplay_label_width(label_characters)
         + gameplay_column_gap() + gameplay_digit_outer_half_width()
         + float(next_extend_digit_count - 1) * gameplay_digit_spacing();
}

float gameplay_top_digit_y() {
    if (gameplay_layout_stacks()) {
        float top_margin = 2.0 * gameplay_label_pixel_height();
        return -1.0 + top_margin + 8.0 * gameplay_label_pixel_height()
             + gameplay_digit_outer_half_height();
    }
    return -1.0 + 2.5 * gameplay_digit_outer_half_height();
}

float gameplay_right_row_step() {
    return 3.6 * gameplay_digit_outer_half_height();
}

float gameplay_bottom_digit_y() {
    return 1.0 - 2.5 * gameplay_digit_outer_half_height();
}

float gameplay_speed_digit_y() {
    return gameplay_bottom_digit_y() - 3.0 * gameplay_digit_outer_half_height();
}

float gameplay_label_y_for_height(float digit_y, float digit_outer_half_height) {
    if (gameplay_layout_stacks()) {
        float row_gap = gameplay_label_pixel_height();
        return digit_y - digit_outer_half_height - row_gap
             - 7.0 * gameplay_label_pixel_height();
    }
    return digit_y + digit_outer_half_height
         - 7.0 * gameplay_label_pixel_height();
}

float gameplay_label_y(float digit_y) {
    return gameplay_label_y_for_height(digit_y, gameplay_digit_outer_half_height());
}

float title_text_scale() {
    return clamp(frame.aspect / (16.0 / 9.0), 0.48, 1.0);
}

float title_overlay_text_scale() {
    return clamp(frame.aspect / (16.0 / 9.0), 0.48, 1.0);
}

float title_detail_pixel_height() {
    return font_pixel_height(0.0065 * title_text_scale());
}

float title_detail_pixel_width() {
    return title_detail_pixel_height() / frame.aspect;
}

float title_detail_label_x() {
    return 0.52;
}

bool title_details_stack() {
    return frame.aspect < 1.10;
}

float title_detail_value_x() {
    if (title_details_stack()) return title_detail_label_x();
    float widest_label_width = 35.0 * title_detail_pixel_width();
    return title_detail_label_x() + widest_label_width
         + 4.0 * title_detail_pixel_width();
}

float title_grade_center_y(int grade) {
    // Start directly under the wordmark and keep explicit breathing room
    // between complete difficulty cards. The lower half remains available for
    // the footer whose row count changes in godmode.
    return -0.58 + float(grade) * 0.34;
}

float title_digit_outer_half_height();

float title_detail_digit_y(int grade, int row) {
    if (title_details_stack()) {
        float label_y = title_grade_center_y(grade) + 0.035 + float(row) * 0.065;
        return label_y + 7.0 * title_detail_pixel_height()
             + title_detail_pixel_height() + title_digit_outer_half_height();
    }
    return title_grade_center_y(grade) + 0.09 + float(row) * 0.082;
}

float title_digit_spacing() {
    return 0.060 * title_text_scale() / frame.aspect;
}

float title_digit_outer_half_width() {
    return 0.0165 * title_text_scale() / frame.aspect;
}

float title_digit_outer_half_height() {
    return 0.027 * title_text_scale();
}

float title_detail_label_y(int grade, int row) {
    if (title_details_stack()) {
        return title_grade_center_y(grade) + 0.035 + float(row) * 0.065;
    }
    return title_detail_digit_y(grade, row) + title_digit_outer_half_height()
         - 7.0 * title_detail_pixel_height();
}

int title_footer_row_count() {
    return (frame.state & TT_HUD_GOD_MODE) != 0 ? 5 : 4;
}

float title_footer_row_y(int row) {
    int row_count = title_footer_row_count();
    return mix(0.50, 0.90, float(row) / float(row_count - 1));
}

float title_volume_digit_y() {
    return title_footer_row_y(0);
}

int title_footer_row_for_group(int group) {
    bool tune_visible = (frame.state & TT_HUD_GOD_MODE) != 0;
    if (group == 12) return 0;
    if (group == 16) return 1;
    if (group == 15) return 2;
    if (group == 13) return tune_visible ? 3 : 2;
    return tune_visible ? 4 : 3;
}

float title_footer_label_y(float digit_y) {
    return digit_y + title_digit_outer_half_height()
         - 7.0 * title_detail_pixel_height();
}

vec3 rotate_x(vec3 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return vec3(point.x, point.y * cosine - point.z * sine,
                point.y * sine + point.z * cosine);
}

vec3 rotate_y(vec3 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return vec3(point.x * cosine + point.z * sine, point.y,
                -point.x * sine + point.z * cosine);
}

vec3 rotate_z(vec3 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return vec3(point.x * cosine - point.y * sine,
                point.x * sine + point.y * cosine, point.z);
}

vec3 transform_title_point(vec3 point) {
    // Fixed-function OpenGL applied the last model rotation first.
    point = rotate_z(point, frame.time * 0.20943951);
    point = rotate_y(point, sin(frame.time * 0.3) * 0.20943951);
    point = rotate_x(point, 0.52359878);
    // Leave a stable blank column on the right for the title menu.
    return point + vec3(3.70, 1.8, 3.5);
}

vec3 title_torus_point(int major_index, int minor_index) {
    const float tau = 6.283185307179586;
    float major_angle = float(major_index % title_major_segments) *
                        tau / float(title_major_segments);
    float minor_angle = float(minor_index % title_minor_segments) *
                        tau / float(title_minor_segments);
    float radius = 4.9 + cos(minor_angle) * 0.45;
    return transform_title_point(vec3(sin(major_angle) * radius,
                                      cos(major_angle) * radius,
                                      sin(minor_angle) * 0.7));
}

vec2 project_title_point(vec3 point) {
    // Match the original eye at (0, 0, -1) and its near-plane frustum.
    float eye_depth = max(point.z + 1.0, 0.1);
    return vec2(-point.x / eye_depth,
                -point.y * frame.aspect / eye_depth);
}

float title_wordmark_origin_x(float pixel_height) {
    // A hard maximum snaps its velocity whenever a different polygon corner
    // becomes the rightmost point. This exponential weighted edge follows the
    // complete silhouette continuously while remaining close to its boundary.
    const float edge_sharpness = 48.0;
    float weighted_edge = 0.0;
    float total_weight = 0.0;
    for (int major = 0; major < title_major_segments; ++major) {
        for (int minor = 0; minor < title_minor_segments; ++minor) {
            vec2 projected = project_title_point(title_torus_point(major, minor));
            float weight = exp(clamp(projected.x, -2.0, 1.0) * edge_sharpness);
            weighted_edge += projected.x * weight;
            total_weight += weight;
        }
    }
    float torus_edge = total_weight > 0.0 ? weighted_edge / total_weight : 0.40;
    // Include the small, bounded soft-edge underestimate in the requested
    // physical clearance. This yields about twenty pixels at common sizes.
    float physical_gap = 0.10 / frame.aspect;
    float wordmark_width = float(title_wordmark_characters * 6 - 1)
        * pixel_height / frame.aspect;
    return min(torus_edge + physical_gap, 0.96 - wordmark_width);
}

void draw_title_mask_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - title_mask_offset;
    int corner = vertex % 6;
    int torus_mask_vertex_count = title_major_segments * 6 +
                                  title_major_segments * title_minor_segments * 6;
    if (vertex >= torus_mask_vertex_count) {
        vec2 panel_corners[6] = vec2[](
            vec2(0.32, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
            vec2(0.32, -1.0), vec2(1.0, 1.0), vec2(0.32, 1.0)
        );
        glyph_color = color_black;
        glyph_alpha = 1.0;
        gl_Position = vec4(panel_corners[corner], 0.0, 1.0);
        return;
    }
    vec3 points[4];
    if (vertex < title_major_segments * 6) {
        int segment = vertex / 6;
        const float tau = 6.283185307179586;
        float angle_a = float(segment) * tau / float(title_major_segments);
        float angle_b = float(segment + 1) * tau / float(title_major_segments);
        points = vec3[](
            transform_title_point(vec3(sin(angle_a) * 5.35, cos(angle_a) * 5.35, 0.0)),
            transform_title_point(vec3(sin(angle_a) * 12.0, cos(angle_a) * 12.0, 0.0)),
            transform_title_point(vec3(sin(angle_b) * 12.0, cos(angle_b) * 12.0, 0.0)),
            transform_title_point(vec3(sin(angle_b) * 5.35, cos(angle_b) * 5.35, 0.0))
        );
    } else {
        int cell = (vertex - title_major_segments * 6) / 6;
        int major = cell / title_minor_segments;
        int minor = cell % title_minor_segments;
        points = vec3[](
            title_torus_point(major, minor),
            title_torus_point(major, minor + 1),
            title_torus_point(major + 1, minor + 1),
            title_torus_point(major + 1, minor)
        );
    }
    const int corner_index[6] = int[](0, 1, 2, 0, 2, 3);
    glyph_color = color_black;
    glyph_alpha = 1.0;
    gl_Position = vec4(project_title_point(points[corner_index[corner]]), 0.0, 1.0);
}

void draw_title_torus_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - title_torus_offset;
    int line = vertex / 6;
    int corner = vertex % 6;
    int edge_count = title_major_segments * title_minor_segments;
    int cell = line % edge_count;
    int major_index = cell / title_minor_segments;
    int minor_index = cell % title_minor_segments;
    bool minor_edge = line >= edge_count;
    vec3 point_a = title_torus_point(major_index, minor_index);
    vec3 point_b = minor_edge
        ? title_torus_point(major_index, minor_index + 1)
        : title_torus_point(major_index + 1, minor_index);
    vec2 start = project_title_point(point_a);
    vec2 end = project_title_point(point_b);
    vec2 direction = normalize(end - start);
    vec2 normal = vec2(-direction.y / frame.aspect, direction.x) * 0.0017;
    vec2 line_corners[6] = vec2[](
        start - normal, end - normal, end + normal,
        start - normal, end + normal, start + normal
    );
    float shimmer = 0.82 + 0.18 * sin(frame.time * 1.7 + point_a.z * 18.0);
    glyph_color = vec3(shimmer);
    gl_Position = vec4(line_corners[corner], 0.0, 1.0);
}

void draw_title_wordmark_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - title_wordmark_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int row_mask = character_glyph_row(title_wordmark_codes[character], row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    float pixel_height = font_pixel_height(0.0085 * responsive_text_scale());
    float pixel_width = pixel_height / frame.aspect;
    vec2 origin = vec2(title_wordmark_origin_x(pixel_height), -0.86);
    vec2 cell = origin + vec2(float(character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    float pulse = 0.88 + sin(frame.time * 1.3 + float(character) * 0.24) * 0.12;
    glyph_color = mix(color_title_sky_blue, color_title_lavender,
                      float(character) / float(title_wordmark_characters - 1)) * pulse;
    gl_Position = vec4(position, 0.0, 1.0);
}

vec2 title_grade_center(int grade) {
    return vec2(0.46, title_grade_center_y(grade));
}

vec3 title_grade_color(int grade) {
    if (grade == 0) return color_title_sky_blue;
    if (grade == 1) return color_hard_amber;
    return color_extreme_pink;
}

void draw_title_grade_ring_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - title_grade_ring_offset;
    int line = vertex / 6;
    int corner = vertex % 6;
    int grade = line / title_grade_ring_segments;
    int segment = line % title_grade_ring_segments;
    bool selected = frame.remaining_time_ms == grade;
    bool menu_active = selected;
    float radius = selected
        ? 0.064 + (menu_active ? sin(frame.time * 5.0) * 0.009 : 0.0)
        : 0.052;
    const float tau = 6.283185307179586;
    float angle_a = float(segment) * tau / float(title_grade_ring_segments);
    float angle_b = float(segment + 1) * tau / float(title_grade_ring_segments);
    vec2 center = title_grade_center(grade);
    vec2 start = center + vec2(cos(angle_a) * radius / frame.aspect,
                               sin(angle_a) * radius);
    vec2 end = center + vec2(cos(angle_b) * radius / frame.aspect,
                             sin(angle_b) * radius);
    vec2 direction = normalize(end - start);
    float thickness = selected ? (menu_active ? 0.0032 : 0.0022) : 0.0015;
    vec2 normal = vec2(-direction.y / frame.aspect, direction.x) * thickness;
    vec2 line_corners[6] = vec2[](
        start - normal, end - normal, end + normal,
        start - normal, end + normal, start + normal
    );
    glyph_color = title_grade_color(grade) * (selected ? 1.0 : 0.48);
    gl_Position = vec4(line_corners[corner], 0.0, 1.0);
}

void draw_title_grade_label_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - title_grade_label_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    // NORMAL/HARD/EXTREME each own a LEVEL, BEST and DONE detail row. Reuse
    // the compact source glyph table while laying those labels out as three
    // responsive cards followed by SETTINGS, HELP, EXIT and the godmode TUNE item.
    const int group_starts[17] = int[](
        0, 6, 11, 15, 19, 23, 28, 32, 36, 43, 48, 52, 56, 64, 68, 72, 76
    );
    const int label_codes[83] = int[](
        14, 15, 18, 13, 1, 12, 12, 5, 22, 5, 12, 2, 5, 19, 20, 4, 15, 14, 5,
        8, 1, 18, 4, 12, 5, 22, 5, 12, 2, 5, 19, 20, 4, 15, 14, 5,
        5, 24, 20, 18, 5, 13, 5, 12, 5, 22, 5, 12, 2, 5, 19, 20, 4, 15, 14, 5,
        19, 5, 20, 20, 9, 14, 7, 19, 8, 5, 12, 16, 5, 24, 9, 20, 20, 21, 14, 5, 18, 5, 16, 12, 1, 25, 19
    );
    int group = 0;
    for (int candidate = 1; candidate < 17; ++candidate) {
        if (character >= group_starts[candidate]) group = candidate;
    }
    int local_character = character - group_starts[group];
    int row_mask = character_glyph_row(label_codes[character], row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    int grade = group < 12 ? group / 4 : -1;
    int grade_row = group < 12 ? group % 4 : -1;
    float pixel_height = font_pixel_height(grade_row == 0
        ? 0.0085 * title_text_scale() : title_detail_pixel_height());
    float pixel_width = pixel_height / frame.aspect;
    vec2 origin;
    if (grade >= 0) {
        origin = grade_row == 0
            ? vec2(title_detail_label_x(), title_grade_center_y(grade)
                   - 3.5 * pixel_height)
            : vec2(title_detail_label_x(), title_detail_label_y(grade,
                   grade_row - 1));
    } else if (group == 12) {
        origin = vec2(title_detail_label_x(),
                      title_footer_label_y(title_volume_digit_y()));
    } else {
        origin = vec2(title_detail_label_x(),
                      title_footer_row_y(title_footer_row_for_group(group)));
    }
    vec2 cell = origin + vec2(float(local_character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    bool active_grade = grade >= 0 && frame.remaining_time_ms == grade;
    bool menu_active = active_grade || (group == 12 && frame.remaining_time_ms == TT_MENU_SETTINGS)
               || (group == 13 && frame.remaining_time_ms == TT_MENU_HELP)
               || (group == 15 && frame.remaining_time_ms == TT_MENU_TUNE)
               || (group == 14 && frame.remaining_time_ms == TT_MENU_EXIT)
               || (group == 16 && frame.remaining_time_ms == TT_MENU_REPLAYS);
    glyph_color = menu_active && (grade_row <= 1 || grade < 0) ? color_ui_value_ice_white
                : grade_row == 0 ? color_ui_label_blue_gray
                : grade >= 0 && grade_row > 1 ? color_ui_muted_slate : color_ui_label_blue_gray;
    if (group == 15 && (frame.state & TT_HUD_GOD_MODE) == 0) position = vec2(2.0);
    gl_Position = vec4(position, 0.0, 1.0);
}

void draw_gameplay_overlay_vertex() {
    bool game_over = (frame.state & TT_HUD_GAME_OVER) != 0;
    bool paused = (frame.state & TT_HUD_PAUSED) != 0 && !game_over;
    // Bit 5 is driven from wall time, which continues while the simulation and
    // its presentation clock are paused. This retains clean screenshot gaps
    // without ever freezing PAUSE indefinitely in its invisible phase.
    bool pause_visible = (frame.state & TT_HUD_PAUSE_OVERLAY) != 0;
    if (!game_over && (!paused || !pause_visible)) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - gameplay_overlay_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int row_mask = character_glyph_row(game_over ? game_over_codes[character]
                                            : paused_codes[character], row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    float pixel_height = font_pixel_height((game_over ? 0.036 : 0.032) * responsive_text_scale());
    float pixel_width = pixel_height / frame.aspect;
    int visible_characters = game_over ? gameplay_overlay_characters : 5;
    float word_width = float(visible_characters * 6 - 1) * pixel_width;
    vec2 origin = vec2(-word_width * 0.5, -0.12);
    vec2 cell = origin + vec2(float(character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    glyph_color = game_over ? color_game_over_red : color_pause_cyan;
    ignore_transition = 1.0;
    gl_Position = vec4(position, 0.0, 1.0);
}

void draw_next_extend_vertex() {
    if ((frame.state & TT_HUD_TITLE) != 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - next_extend_offset;
    float text_scale = responsive_text_scale();
    float spacing = 0.052 * text_scale / frame.aspect;
    if (vertex < next_extend_digit_count * 42) {
        int glyph = vertex / 42;
        int segment = (vertex / 6) % 7;
        int corner = vertex % 6;
        int remaining = max(frame.next_extend_score - frame.score, 0);
        int digit = decimal_digit(remaining, glyph);
        bool enabled = (digit_masks[digit] & (1 << segment)) != 0;
        vec2 centers[7] = vec2[](
            vec2(0, -1), vec2(1, -0.5), vec2(1, 0.5), vec2(0, 1),
            vec2(-1, 0.5), vec2(-1, -0.5), vec2(0, 0)
        );
        bool horizontal = segment == 0 || segment == 3 || segment == 6;
        vec2 half_size = horizontal ? vec2(0.014 * text_scale / frame.aspect, 0.0027 * text_scale)
                                    : vec2(0.0027 * text_scale / frame.aspect, 0.0125 * text_scale);
        vec2 center = centers[segment] * vec2(0.014 * text_scale / frame.aspect, 0.026 * text_scale);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(gameplay_right_label_x(), next_extend_digit_count)
            : gameplay_row_value_anchor(8);
        vec2 anchor = vec2(value_anchor - float(glyph) * spacing,
                           gameplay_top_digit_y() + gameplay_right_row_step());
        vec2 position = anchor + center + corners[corner] * half_size;
        if (!enabled) position = vec2(2.0);
        glyph_color = color_ui_value_ice_white;
        gl_Position = vec4(position, 0.0, 1.0);
        return;
    }
}

int time_change_row(int character, int row, int seconds) {
    int absolute_seconds = abs(seconds);
    if (character == 0) {
        if (seconds < 0) return row == 3 ? 31 : 0;
        return row == 1 || row == 2 || row == 4 || row == 5 ? 4
             : (row == 3 ? 31 : 0);
    }
    if (character == 1) return character_glyph_row(27 + absolute_seconds / 10, row);
    if (character == 2) return character_glyph_row(27 + absolute_seconds % 10, row);
    if (character == 4) return character_glyph_row(19, row);
    if (character == 5) return character_glyph_row(5, row);
    if (character == 6) {
        const int c_rows[7] = int[](15, 16, 16, 16, 16, 16, 15);
        return c_rows[row];
    }
    if (character == 7) return row == 6 ? 4 : 0;
    return 0;
}

void draw_time_change_vertex() {
    bool visible = frame.time_change_ticks >= 0 &&
                   frame.time_change_ticks % 64 > 32;
    if (!visible || (frame.state & (TT_HUD_TITLE | TT_HUD_GAME_OVER)) != 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - time_change_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int row_mask = time_change_row(character, row, frame.time_change_seconds);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    float pixel_height = font_pixel_height(0.018 * responsive_text_scale());
    float pixel_width = pixel_height / frame.aspect;
    float word_width = float(time_change_characters * 6 - 1) * pixel_width;
    vec2 origin = vec2(-word_width * 0.5, -0.66);
    vec2 cell = origin + vec2(float(character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    glyph_color = frame.time_change_seconds < 0 ? color_time_penalty_red
                                                : color_time_bonus_green;
    gl_Position = vec4(position, 0.0, 1.0);
}

void draw_gameplay_label_vertex() {
    if ((frame.state & TT_HUD_TITLE) != 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - gameplay_label_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int row_mask = character_glyph_row(gameplay_label_codes[character], row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    int group = character < 5 ? 0 : character < 9 ? 1
              : character < 14 ? 2 : character < 18 ? 3
              : character < 22 ? 4 : character < 31 ? 5
              : character < 39 ? 6 : 7;
    const int starts[8] = int[](0, 5, 9, 14, 18, 22, 31, 39);
    const float fixed_x[8] = float[](
        0.0, -0.18, -0.94, 0.68, 0.50, -0.68, -0.24, 0.0
    );
    float top_digit_y = gameplay_top_digit_y();
    float digit_y = group < 2 ? top_digit_y
        : group == 7 ? top_digit_y + gameplay_right_row_step()
        : group == 4 ? gameplay_speed_digit_y()
        : gameplay_bottom_digit_y();
    float origin_x = group == 0 || group == 7 ? gameplay_right_label_x()
                                              : fixed_x[group];
    float origin_y = group == 7
        ? gameplay_label_y_for_height(digit_y, next_extend_digit_outer_half_height())
        : gameplay_label_y(digit_y);
    vec2 origin = vec2(origin_x, origin_y);
    float pixel_height = font_pixel_height(gameplay_label_pixel_height());
    float pixel_width = pixel_height / frame.aspect;
    int local_character = character - starts[group];
    vec2 cell = origin + vec2(float(local_character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    glyph_color = color_ui_label_blue_gray;
    gl_Position = vec4(position, 0.0, 1.0);
}

void draw_fps_vertex() {
    if ((frame.state & TT_HUD_TITLE) != 0 || (frame.state & TT_HUD_FPS_VISIBLE) == 0) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - fps_offset;
    int pixel = vertex / 6;
    int corner = vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int fps = (frame.state >> TT_HUD_FPS_SHIFT) & TT_HUD_FPS_MASK;
    int code = character < 4 ? fps_label_codes[character]
             : 27 + decimal_digit(fps, 6 - character);
    bool leading_zero = (character == 4 && fps < 100) ||
                        (character == 5 && fps < 10);
    int row_mask = leading_zero ? 0 : character_glyph_row(code, row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    float pixel_height = font_pixel_height(gameplay_label_pixel_height());
    float pixel_width = pixel_height / frame.aspect;
    vec2 origin = vec2(-0.94, gameplay_label_y(gameplay_top_digit_y()));
    vec2 cell = origin + vec2(float(character * 6 + column) * pixel_width,
                              float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    glyph_color = character < 4 ? color_ui_label_blue_gray : color_ui_value_ice_white;
    gl_Position = vec4(position, 0.0, 1.0);
}

int character_glyph_row(int code, int row) {
    if (code >= 1 && code <= 26) {
        return character_letter_rows[(code - 1) * 7 + row];
    }
    if (code >= 27 && code <= 36) {
        return character_digit_rows[(code - 27) * 7 + row];
    }
    if (code >= 42 && code <= 77) {
        return character_extended_rows[(code - 42) * 7 + row];
    }
    if (code == 37) return row <= 4 ? 1 << row : 0;
    if (code == 38) return row == 3 ? 31 : (row == 1 || row == 2 || row == 4 || row == 5 ? 4 : 0);
    if (code == 39) return row == 3 ? 31 : 0;
    if (code == 40) return row == 6 ? 4 : 0;
	if (code == 41) return row == 5 ? 4 : (row == 6 ? 8 : 0);
    return 0;
}

int settings_glyph_code(int line, int column) {
    const int heading[8] = int[](19, 5, 20, 20, 9, 14, 7, 19);
    const int volume_prefix[9] = int[](22, 15, 12, 21, 13, 5, 0, 39, 0);
    const int percent[7] = int[](16, 5, 18, 3, 5, 14, 20);
    const int antialiasing_prefix[16] = int[](
        1, 14, 20, 9, 0, 1, 12, 9, 1, 19, 9, 14, 7, 0, 39, 0
    );
    const int near_blur_prefix[12] = int[](
        14, 5, 1, 18, 0, 2, 12, 21, 18, 0, 39, 0
    );
    const int near_fade_prefix[12] = int[](
        14, 5, 1, 18, 0, 6, 1, 4, 5, 0, 39, 0
    );
	const int rear_track_prefix[19] = int[](
		18, 5, 1, 18, 0, 20, 18, 1, 3, 11, 0, 2, 12, 5, 14, 4, 0, 39, 0
	);
    const int track_draw_prefix[17] = int[](
        16, 1, 14, 5, 12, 0, 4, 9, 19, 20, 1, 14, 3, 5, 0, 39, 0
    );
    const int wire_draw_prefix[16] = int[](
        23, 9, 18, 5, 0, 4, 9, 19, 20, 1, 14, 3, 5, 0, 39, 0
    );
    const int border_draw_prefix[18] = int[](
        2, 15, 18, 4, 5, 18, 0, 4, 9, 19, 20, 1, 14, 3, 5, 0, 39, 0
    );
    const int shot_distance_prefix[16] = int[](
        19, 8, 15, 20, 0, 4, 9, 19, 20, 1, 14, 3, 5, 0, 39, 0
    );
    const int fps_limit_prefix[12] = int[](
        6, 16, 19, 0, 12, 9, 13, 9, 20, 0, 39, 0
    );
    const int panels[6] = int[](16, 1, 14, 5, 12, 19);
    const int slices[6] = int[](19, 12, 9, 3, 5, 19);
    const int back[4] = int[](2, 1, 3, 11);
    if (line == 0 && column < 8) return heading[column];
    if (line == 2) {
        if (column < 9) return volume_prefix[column];
        if (column >= 9 && column < 12)
            return 27 + decimal_digit(frame.time_change_ticks, 11 - column);
        if (column >= 13 && column < 20) return percent[column - 13];
    }
    if (line == 4) {
        if (column < 16) return antialiasing_prefix[column];
        if (int(frame.rotation) <= 1) {
            const int disabled[3] = int[](15, 6, 6);
            if (column >= 16 && column < 19) return disabled[column - 16];
        } else {
            if (column == 16) return 27 + int(frame.rotation);
            if (column == 17) return 24;
        }
    }
    if (line == 6) {
        if (column < 17) return track_draw_prefix[column];
        if (column >= 17 && column < 20)
            return 27 + decimal_digit(frame.track_draw_distance & 1023, 19 - column);
        if (column >= 21 && column < 27) return panels[column - 21];
    }
    if (line == 8) {
		if (column < 16) return wire_draw_prefix[column];
		if (column >= 16 && column < 19)
			return 27 + decimal_digit((frame.track_draw_distance >> 10) & 1023, 18 - column);
		if (column >= 20 && column < 26) return slices[column - 20];
	}
    if (line == 10) {
		if (column < 18) return border_draw_prefix[column];
		if (column >= 18 && column < 21)
			return 27 + decimal_digit((frame.track_draw_distance >> 20) & 1023, 20 - column);
		if (column >= 22 && column < 28) return slices[column - 22];
	}
    if (line == 12) {
		if (column < 16) return shot_distance_prefix[column];
		if (column >= 16 && column < 19)
			return 27 + decimal_digit(frame.title_normal_best_levels, 18 - column);
	}
    if (line == 14) {
		if (column < 12) return fps_limit_prefix[column];
		if (frame.rank_remaining == 60) {
			if (column >= 12 && column < 14)
				return 27 + decimal_digit(frame.rank_remaining, 13 - column);
		} else if (frame.rank_remaining == -1) {
			const int display[7] = int[](4, 9, 19, 16, 12, 1, 25);
			if (column >= 12 && column < 19) return display[column - 12];
		} else {
			const int unlocked[8] = int[](21, 14, 12, 15, 3, 11, 5, 4);
			if (column >= 12 && column < 20) return unlocked[column - 12];
		}
	}
    if (line == 16) {
        if (column < 12) return near_blur_prefix[column];
        if (column >= 12 && column < 15)
            return 27 + decimal_digit(frame.near_blur_percent, 14 - column);
        if (column >= 16 && column < 23) return percent[column - 16];
    }
	if (line == 18) {
		if (column < 12) return near_fade_prefix[column];
		if (column >= 12 && column < 15)
			return 27 + decimal_digit(frame.near_fade_percent, 14 - column);
		if (column >= 16 && column < 23) return percent[column - 16];
	}
	if (line == 20) {
		if (column < 19) return rear_track_prefix[column];
		if (column >= 19 && column < 22)
			return 27 + decimal_digit(frame.rear_track_blend_percent, 21 - column);
		const int percent_label[3] = int[](16, 3, 20);
		if (column >= 23 && column < 26) return percent_label[column - 23];
    }
	if (line == 21) {
		if (column == 2 || column == 23) return 9;
		if (column >= 3 && column < 23)
			return (column - 2) * 5 <= frame.rear_track_blend_percent ? 38 : 39;
	}
	if (line == 22 && column < 4) return back[column];
    return 0;
}

void draw_help_vertex() {
    bool settings_visible = (frame.state & TT_HUD_SETTINGS) != 0;
    bool visible = (frame.state & TT_HUD_TITLE) != 0
        && (frame.remaining_time_ms == TT_MENU_HELP || settings_visible);
    if (!visible) {
        glyph_color = color_black;
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int vertex = gl_VertexIndex - help_offset;
    int page = clamp(frame.time_change_seconds, 0, 2);
    if (vertex < help_diagram_vertex_count) {
        int corner = vertex % 6;
        vec2 panel_corners[6] = vec2[](
            vec2(-0.96, -0.78), vec2(0.28, -0.78), vec2(0.28, 0.94),
            vec2(-0.96, -0.78), vec2(0.28, 0.94), vec2(-0.96, 0.94)
        );
        glyph_color = color_background_navy;
        glyph_alpha = 1.0;
        gl_Position = settings_visible && vertex < 6
            ? vec4(panel_corners[corner], 0.0, 1.0)
            : vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }
    int text_vertex = gl_VertexIndex - help_text_offset;
    int pixel = text_vertex / 6;
    int corner = text_vertex % 6;
    int character = pixel / 35;
    int character_pixel = pixel % 35;
    int row = character_pixel / 5;
    int column = character_pixel % 5;
    int line = character / help_columns;
    int text_column = character % help_columns;
    int code = settings_visible
        ? settings_glyph_code(line, text_column)
		: line < help_source_lines
		? help_characters[page * help_source_character_count + line * help_columns + text_column]
		: 0;
    int row_mask = character_glyph_row(code, row);
    bool enabled = (row_mask & (1 << (4 - column))) != 0;
    float pixel_height = font_pixel_height(0.008 * title_overlay_text_scale());
    float pixel_width = pixel_height / frame.aspect;
    vec2 origin = settings_visible ? vec2(-0.88, -0.76) : vec2(-0.88, -0.70);
    vec2 cell = origin + vec2(float(text_column * 6 + column) * pixel_width,
                              float(line) * (settings_visible ? 0.071 : 0.085)
                              + float(row) * pixel_height);
    vec2 pixel_corners[6] = vec2[](
        vec2(0.16, 0.16), vec2(0.84, 0.16), vec2(0.84, 0.84),
        vec2(0.16, 0.16), vec2(0.84, 0.84), vec2(0.16, 0.84)
    );
    vec2 position = font_dot_position(cell, pixel_height, pixel_corners[corner]);
    if (!enabled) position = vec2(2.0);
    int selected_line = 2 + frame.time_change_seconds * 2;
    glyph_color = line == 0 || (settings_visible && line == selected_line)
        ? color_ui_value_ice_white : color_ui_label_blue_gray;
	if (settings_visible && line == 21 && text_column >= 3 && text_column < 23
		&& (text_column - 2) * 5 <= frame.rear_track_blend_percent)
		glyph_color = color_ui_value_ice_white;
    glyph_alpha = 0.96;
    gl_Position = vec4(position, 0.0, 1.0);
}

int title_level_pair(int grade) {
    return grade == 0 ? frame.hits
         : grade == 1 ? frame.speed : frame.next_extend_score;
}

int title_high_score(int grade) {
    return grade == 0 ? frame.score
         : grade == 1 ? frame.rank : frame.rank_remaining;
}

int title_best_level_pair(int grade) {
    return grade == 0 ? frame.title_normal_best_levels
         : grade == 1 ? frame.title_hard_best_levels
                      : frame.title_extreme_best_levels;
}

// Geometry is drawn once behind menu text, outside the font-outline passes.
void draw_menu_selection_vertex() {
    if ((frame.state & TT_HUD_TITLE) == 0) {
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        glyph_color = color_black;
        return;
    }
    bool settings = (frame.state & TT_HUD_SETTINGS) != 0;
    float left = 0.39;
    float right = 0.985;
    float top;
    float bottom;
    if (settings) {
        int line = 2 + clamp(frame.time_change_seconds, 0, 10) * 2;
        float pitch = font_pixel_height(0.008 * title_overlay_text_scale());
        top = -0.76 + float(line) * 0.071 - 0.014;
        bottom = top + 7.0 * pitch + 0.028;
        left = -0.93;
        right = 0.25;
    } else if (frame.remaining_time_ms >= TT_MENU_NORMAL && frame.remaining_time_ms <= TT_MENU_EXTREME) {
        float center = title_grade_center_y(frame.remaining_time_ms);
        top = center - 0.077;
        bottom = center + 0.077;
    } else {
        int item = frame.remaining_time_ms;
        int group = item == 3 ? 12 : item == 4 ? 13 : item == 5 ? 15
                  : item == 6 ? 14 : 16;
        float label_y = group == 12 ? title_footer_label_y(title_volume_digit_y())
                       : title_footer_row_y(title_footer_row_for_group(group));
        top = label_y - 0.018;
        bottom = label_y + 7.0 * title_detail_pixel_height() + 0.018;
    }
    int vertex = gl_VertexIndex - menu_selection_offset;
    int part = vertex / 6;
    int corner = vertex % 6;
    float thickness = font_pixel_height(0.003);
    float horizontal = thickness / frame.aspect;
    vec2 start = vec2(left, top);
    vec2 end = vec2(right, bottom);
    glyph_color = color_selection_dark_teal;
    glyph_alpha = 0.98;
    if (part == 1) { end.x = left + horizontal * 2.0; }
    if (part == 2) { end.y = top + thickness; }
    if (part == 3) { start.y = bottom - thickness; }
    if (part == 4) { start.x = right - horizontal; }
    if (part > 0) {
        glyph_color = color_ui_active_cyan;
        glyph_alpha = 1.0;
    }
    vec2 quad[6] = vec2[](vec2(0,0), vec2(1,0), vec2(1,1),
                          vec2(0,0), vec2(1,1), vec2(0,1));
    vec2 position = mix(start, end, quad[corner]);
    if (part == 5) {
        float center = (top + bottom) * 0.5;
        float arrow_height = min((bottom - top) * 0.22, 0.018);
        float arrow_left = left + horizontal * 4.0;
        vec2 triangle[3] = vec2[](vec2(arrow_left, center - arrow_height),
                                 vec2(arrow_left + arrow_height / frame.aspect, center),
                                 vec2(arrow_left, center + arrow_height));
        // A degenerate second triangle avoids drawing the arrow twice.
        position = triangle[corner < 3 ? corner : 2];
    }
    gl_Position = vec4(position, 0.0, 1.0);
}

void draw_replay_library_vertex() {
    ignore_transition = 1.0;
    int vertex = gl_VertexIndex - (menu_selection_offset + menu_selection_vertex_count);
    vec2 quad[6] = vec2[](vec2(0,0), vec2(1,0), vec2(1,1),
                          vec2(0,0), vec2(1,1), vec2(0,1));
    if (vertex < 6) {
        glyph_color = color_replay_panel_navy;
        glyph_alpha = 0.98;
        vec2 position = quad[vertex] * 2.0 - 1.0;
        if (frame.remaining_time_ms >= 2) {
            float top = frame.time - 0.007;
            position = mix(vec2(-0.97, top), vec2(0.97, top + 0.074), quad[vertex]);
            glyph_color = color_selection_dark_teal;
            if (frame.remaining_time_ms == 3) {
                position.x = -0.97 + quad[vertex].x * 0.008;
                glyph_color = color_ui_active_cyan;
            }
            glyph_alpha = 1.0;
        }
        gl_Position = vec4(position, 0, 1);
        return;
    }
    vertex -= 6;
    int pixel = vertex / 6;
    int character = pixel / 35;
    uint words[10] = uint[](frame.text0, frame.text1, frame.text2, frame.text3,
        frame.text4, frame.text5, uint(frame.title_normal_best_levels),
        uint(frame.title_hard_best_levels), frame.text8, uint(frame.speed));
    int code = int((words[character / 4] >> uint((character % 4) * 8)) & 255u);
    int row = (pixel % 35) / 5;
    int column = pixel % 5;
    float pitch = intBitsToFloat(frame.near_blur_percent);
    vec2 position = vec2(frame.view_angle, frame.time) +
        (vec2(character * 6 + column, row) + 0.16 + quad[vertex % 6] * 0.68)
        * vec2(pitch / frame.aspect, pitch);
    if ((character_glyph_row(code, row) & (1 << (4 - column))) == 0)
        position = vec2(2);
    glyph_color = frame.zone == 1 ? color_ui_value_ice_white : color_ui_label_blue_gray;
    if (frame.hits == 0) glyph_color = color_ui_value_ice_white;
    glyph_alpha = 1.0;
    gl_Position = vec4(position, 0, 1);
}

void main() {
    ignore_transition = 0.0;
    if ((frame.state & TT_HUD_REPLAY_LIBRARY) != 0) { draw_replay_library_vertex(); return; }
    // The source glyphs combine a half-alpha face with an opaque outline.
    // This single-pass font uses their average coverage during gameplay.
    glyph_alpha = (frame.state & TT_HUD_TITLE) != 0 ? 0.92 : 0.62;
    if (gl_VertexIndex >= menu_selection_offset) {
        draw_menu_selection_vertex();
        return;
    }
    if (gl_VertexIndex >= help_offset) {
        draw_help_vertex();
        return;
    }
    if (gl_VertexIndex >= fps_offset) {
        draw_fps_vertex();
        return;
    }
    if (gl_VertexIndex >= gameplay_label_offset) {
        draw_gameplay_label_vertex();
        return;
    }
    if (gl_VertexIndex >= time_change_offset) {
        draw_time_change_vertex();
        return;
    }
    if (gl_VertexIndex >= next_extend_offset) {
        draw_next_extend_vertex();
        return;
    }
    if (gl_VertexIndex >= gameplay_overlay_offset) {
        draw_gameplay_overlay_vertex();
        return;
    }
    if (gl_VertexIndex >= title_grade_label_offset) {
        draw_title_grade_label_vertex();
        return;
    }
    if (gl_VertexIndex >= title_grade_ring_offset) {
        draw_title_grade_ring_vertex();
        return;
    }
    if (gl_VertexIndex >= title_wordmark_offset) {
        draw_title_wordmark_vertex();
        return;
    }
    if (gl_VertexIndex >= title_torus_offset) {
        draw_title_torus_vertex();
        return;
    }
    if (gl_VertexIndex < digit_vertex_offset) {
        draw_title_mask_vertex();
        return;
    }
    int digit_vertex = gl_VertexIndex - digit_vertex_offset;
    int glyph = digit_vertex / 42;
    int segment = (digit_vertex / 6) % 7;
    int corner = digit_vertex % 6;
    int digit;
    vec2 anchor;
    float text_scale = responsive_text_scale();
    float spacing = 0.052 * text_scale / frame.aspect;

    if ((frame.state & TT_HUD_TITLE) != 0) {
        float title_spacing = title_digit_spacing();
        float title_start = title_detail_value_x() + title_digit_outer_half_width();
        if (glyph < 63) {
            int grade = glyph / 21;
            int field_glyph = glyph % 21;
            int field = field_glyph / 7;
            int local_glyph = field_glyph % 7;
            int level_pair = title_level_pair(grade);
            int best_level_pair = title_best_level_pair(grade);
            if (field == 0) {
                int level = level_pair % 1000;
                int maximum = level_pair / 1000;
                digit = local_glyph < 3 ? decimal_digit(level, 2 - local_glyph)
                    : local_glyph == 3 ? 10
                    : decimal_digit(maximum, 6 - local_glyph);
            } else if (field == 1) {
                digit = decimal_digit(title_high_score(grade), 6 - local_glyph);
            } else {
                int start_level = best_level_pair % 1000;
                int end_level = best_level_pair / 1000;
                digit = local_glyph < 3 ? decimal_digit(start_level, 2 - local_glyph)
                    : local_glyph == 3 ? 10
                    : decimal_digit(end_level, 6 - local_glyph);
            }
            anchor = vec2(title_start + float(local_glyph) * title_spacing,
                          title_detail_digit_y(grade, field));
            bool active_level = field == 0 && frame.remaining_time_ms == grade;
            glyph_color = active_level ? color_ui_active_cyan
                        : field == 0 ? color_ui_value_ice_white : color_ui_muted_slate;
        } else {
            digit = 0;
            anchor = vec2(2.0);
            glyph_color = color_black;
        }
    } else if (glyph < 7) {
        digit = decimal_digit(frame.score, glyph);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(gameplay_right_label_x(), 7)
            : gameplay_row_value_anchor(5);
        anchor = vec2(value_anchor - float(glyph) * spacing,
                      gameplay_top_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else if (glyph < 14) {
        int time_ms = max(frame.remaining_time_ms, 0);
        int place = glyph - 7;
        if (place < 3) {
            digit = decimal_digit(time_ms % 1000, place);
        } else if (place < 5) {
            digit = decimal_digit((time_ms / 1000) % 60, place - 3);
        } else {
            digit = decimal_digit(time_ms / 60000, place - 5);
        }
        float group_gap = (place >= 3 ? 0.014 : 0.0) +
                          (place >= 5 ? 0.014 : 0.0);
        anchor = vec2(0.14 - float(place) * spacing - group_gap * text_scale / frame.aspect,
                      gameplay_top_digit_y());
        glyph_color = time_ms <= 15000 ? color_ui_warning_orange : color_ui_value_ice_white;
    } else if (glyph < 16) {
        digit = decimal_digit(frame.zone, glyph - 14);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(-0.94, 2) : -0.75;
        anchor = vec2(value_anchor - float(glyph - 14) * spacing,
                      gameplay_bottom_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else if (glyph < 18) {
        digit = decimal_digit(frame.hits, glyph - 16);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(0.68, 2) : 0.94;
        anchor = vec2(value_anchor - float(glyph - 16) * spacing,
                      gameplay_bottom_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else if (glyph < 23) {
        digit = decimal_digit(frame.speed, glyph - 18);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(0.50, 5) : 0.45;
        anchor = vec2(value_anchor - float(glyph - 18) * spacing,
                      gameplay_speed_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else if (glyph < 26) {
        digit = decimal_digit(frame.rank, glyph - 23);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(-0.68, 3) : -0.35;
        anchor = vec2(value_anchor - float(glyph - 23) * spacing,
                      gameplay_bottom_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else if (glyph < 29) {
        digit = decimal_digit(frame.rank_remaining, glyph - 26);
        float value_anchor = gameplay_layout_stacks()
            ? gameplay_stacked_value_anchor(-0.24, 3) : 0.08;
        anchor = vec2(value_anchor - float(glyph - 26) * spacing,
                      gameplay_bottom_digit_y());
        glyph_color = color_ui_value_ice_white;
    } else {
        digit = 0;
        anchor = vec2(2.0);
        glyph_color = color_black;
    }

    bool enabled = (digit_masks[digit] & (1 << segment)) != 0;
    vec2 centers[7] = vec2[](
        vec2(0, -1), vec2(1, -0.5), vec2(1, 0.5), vec2(0, 1),
        vec2(-1, 0.5), vec2(-1, -0.5), vec2(0, 0)
    );
    bool horizontal = segment == 0 || segment == 3 || segment == 6;
    bool title_mode = (frame.state & TT_HUD_TITLE) != 0;
    float digit_scale = title_mode ? title_text_scale() : text_scale;
    float long_half = title_mode ? 0.0135 : 0.018;
    float short_half = title_mode ? 0.003 : 0.0035;
    float center_y = title_mode ? 0.024 : 0.033;
    vec2 half_size = horizontal
        ? vec2(long_half * digit_scale / frame.aspect, short_half * digit_scale)
        : vec2(short_half * digit_scale / frame.aspect,
               (title_mode ? 0.012 : 0.016) * digit_scale);
    vec2 center = centers[segment] * vec2(long_half * digit_scale / frame.aspect,
                                          center_y * digit_scale);
    vec2 position = anchor + center + corners[corner] * half_size;
    if (!enabled) position = vec2(2.0);
    gl_Position = vec4(position, 0, 1);
}
