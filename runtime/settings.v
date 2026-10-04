module runtime

// Distances count course slices (panels count rows). Zero hides that layer.
pub const minimum_track_draw_distance = 0
pub const maximum_track_draw_distance = 999
pub const default_track_draw_distance = 75
pub const default_wire_draw_distance = 120
pub const default_border_draw_distance = 120
pub const default_rear_track_blend_percent = 10
pub const fps_limit_display = -1
pub const fps_limit_unlocked = 0

// The title HUD reserves three digits for starting levels. God mode exposes
// that complete range without changing normal progression unlocks.
const god_mode_max_start_level = 999

const title_volume_preview_duration_ms = i64(3000)

// Percentages, MSAA samples and window dimensions used for a fresh profile.
pub const default_volume_percent = 35
pub const default_volume = f32(default_volume_percent) / 100
pub const default_antialiasing_samples = 8
pub const default_near_blur_percent = 80
pub const default_near_fade_percent = 65
pub const default_brightness_percent = 100
pub const default_luminosity_percent = 80
const default_brightness = f32(default_brightness_percent) / 100
const default_luminosity = f32(default_luminosity_percent) / 100
pub const default_window_width = 1280
pub const default_window_height = 720

// Presentation durations use elapsed monotonic time, independent of FPS.
const menu_transition_duration_ms = i64(500)
const replay_transition_duration_ms = i64(500)
const game_over_fade_duration_ms = i64(2000)
const game_over_fade_opacity = f32(0.65)
const game_over_auto_return_ms = i64(20_000)
const game_over_restart_delay_ms = i64(1000)

// Sampling intervals below count fixed simulation ticks.
const gameplay_status_interval_ticks = 10
const attract_replay_restart_delay_ticks = 120
// Convert course slices per tick to the arcade speedometer's display units.
const displayed_speed_scale = f32(2500)
