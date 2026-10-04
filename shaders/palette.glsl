#ifndef TT_PALETTE_GLSL
#define TT_PALETTE_GLSL

// Base RGB values use the existing normalized 0..1 palette. Brightness,
// luminosity, transition fades and alpha are applied by each shader.
// Changing a role changes every shader that uses that named color.
const vec3 color_black = vec3(0.0);
const vec3 color_white = vec3(1.0);
// Match tt_background_navy in runtime/vulkan_bridge.h (the framebuffer clear).
const vec3 color_background_navy = vec3(0.008, 0.012, 0.03);

// Menus and gameplay HUD.
const vec3 color_ui_label_blue_gray = vec3(0.82, 0.90, 0.94);
const vec3 color_ui_value_ice_white = vec3(0.94, 0.98, 1.00);
const vec3 color_ui_active_cyan = vec3(0.42, 0.90, 1.00);
const vec3 color_ui_muted_slate = vec3(0.52, 0.62, 0.68);
const vec3 color_ui_warning_orange = vec3(1.00, 0.34, 0.20);
const vec3 color_title_sky_blue = vec3(0.35, 0.85, 1.0);
const vec3 color_title_lavender = vec3(0.80, 0.62, 1.0);
const vec3 color_hard_amber = vec3(1.0, 0.66, 0.24);
const vec3 color_extreme_pink = vec3(1.0, 0.38, 0.82);
const vec3 color_game_over_red = vec3(1.0, 0.22, 0.12);
const vec3 color_pause_cyan = vec3(0.45, 0.90, 1.0);
const vec3 color_time_penalty_red = vec3(1.0, 0.26, 0.16);
const vec3 color_time_bonus_green = vec3(0.42, 1.0, 0.62);
const vec3 color_selection_dark_teal = vec3(0.035, 0.10, 0.16);
const vec3 color_replay_panel_navy = vec3(0.015, 0.025, 0.05);
const vec3 color_calibration_label_ice_blue = vec3(0.80, 0.96, 1.0);
const vec3 color_calibration_label_ink = vec3(0.01, 0.02, 0.04);

// Projectiles, particles, hull materials and course markers.
const vec3 color_shot_gold = vec3(1.0, 0.94, 0.42);
const vec3 color_shot_mint = vec3(0.62, 1.0, 0.86);
const vec3 color_shot_outline_navy = vec3(0.015, 0.035, 0.065);
const vec3 color_enemy_crimson = vec3(0.72, 0.015, 0.16);
const vec3 color_enemy_indigo = vec3(0.12, 0.025, 0.68);
const vec3 color_boss_bit_outline_plum = vec3(0.10, 0.01, 0.18);
const vec3 color_calibration_tunnel_cyan = vec3(0.55, 0.95, 1.0);
const vec3 color_bullet_outline_plum = vec3(0.09, 0.005, 0.16);
const vec3 color_spark_mint = vec3(0.60, 1.0, 0.80);
const vec3 color_jet_blue = vec3(0.30, 0.40, 1.0);
const vec3 color_fragment_edge_coral = vec3(1.0, 0.52, 0.30);
const vec3 color_selection_mint = vec3(0.30, 1.0, 0.92);
const vec3 color_enemy_hull_dark_plum = vec3(0.055, 0.008, 0.085);
const vec3 color_player_hull_dark_teal = vec3(0.008, 0.045, 0.065);
const vec3 color_enemy_trim_orange = vec3(1.0, 0.36, 0.12);
const vec3 color_player_trim_cyan = vec3(0.30, 0.95, 1.0);
const vec3 color_border_pale_yellow = vec3(1.0, 1.0, 0.6);
const vec3 color_final_ring_gold = vec3(1.0, 0.9, 0.5);
const vec3 color_normal_ring_mint = vec3(0.5, 1.0, 0.9);

// Only the named channel pulses; amplitudes preserve the original glow.
const vec3 color_exhaust_orange = vec3(1.0, 0.30, 0.08);
const float exhaust_orange_glow_amplitude = 0.62; // G channel
const vec3 color_player_aqua = vec3(0.42, 0.86, 0.88);
const float player_aqua_glow_amplitude = 0.14; // G channel
const vec3 color_boss_bit_orange = vec3(1.0, 0.30, 0.02);
const float boss_bit_orange_glow_amplitude = 0.20; // G channel
const vec3 color_bullet_orange = vec3(1.0, 0.20, 0.015);
const float bullet_orange_glow_amplitude = 0.24; // G channel
const vec3 color_spark_yellow = vec3(1.0, 0.50, 0.04);
const float spark_yellow_glow_amplitude = 0.48; // G channel
const vec3 color_jet_lilac = vec3(0.90, 0.50, 1.0);
const float jet_lilac_glow_amplitude = 0.20; // G channel
const vec3 color_star_ice_blue = vec3(0.75, 0.82, 1.0);
const float star_ice_blue_glow_amplitude = 0.25; // R channel
const vec3 color_fragment_rust = vec3(0.62, 0.16, 0.10);
const float fragment_rust_glow_amplitude = 0.20; // R channel

#endif
