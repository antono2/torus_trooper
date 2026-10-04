module sim

// Simulation timing. Durations ending in _ticks use the fixed 60 Hz simulation.
// The run clock deliberately consumes 17 ms per tick, preserving replay timing;
// replacing it with 1000 / ticks_per_second would change the released game.
pub const ticks_per_second = 60
pub const default_run_time_ms = 120_000
const run_clock_tick_ms = 17
const clock_warning_start_ms = 15_000
const time_change_display_ticks = 240
const score_extend_seconds = 15
const collision_penalty_seconds = 15
const odd_zone_bonus_seconds = 30
const even_zone_bonus_seconds = 45
const zone_transition_duration_ticks = 60
const palette_transition_duration_ticks = 60
const music_transition_delay_ticks = 90

// Lifecycle: the ship is hidden during the death pause, then respawns immune.
const ship_spawn_invulnerability_ticks = 228
const ship_death_pause_ticks = 40
const ship_respawn_protection_ticks = ship_death_pause_ticks + ship_spawn_invulnerability_ticks
const ship_hit_shake_ticks = 32
const ship_hit_shake_intensity = f32(0.05)
const bullet_disappear_duration_ticks = 45
const bullet_max_age_ticks = 600

// Weapons. Distances are course slices; gun offsets are radians around the tube.
const source_player_shot_distance = f32(35)
const shot_muzzle_depth_offset = f32(0.3)
const shot_bank_angle_ratio = f32(0.1)
const gun_lateral_angle = f32(0.05)
const regular_shot_interval_ticks = 2
const star_shot_interval = 7
pub const charged_shot_min_ticks = 23
const charged_shot_max_ticks = 90
const charged_shot_damage = 100
const charged_shot_base_range = f32(2)
const charged_shot_range_per_tick = f32(0.5)
const charged_shot_base_size = f32(0.1)
const charged_shot_size_per_tick = f32(0.15)
const charging_shot_size_ratio = f32(0.33)
// Side fire is dormant until speed exceeds this multiple of the grade default.
const side_fire_speed_ratio = f32(1.33)
const side_fire_idle_ticks = 99_999

// Ship response coefficients are fractions applied each simulation tick.
// Larger response values approach the target faster; lower bank retention
// damps steering sooner. Turning is radians per tick per unit of bank.
const charge_brake_speed_ratio = f32(0.5)
const regenerative_capture_ratio = f32(0.05)
const regenerative_release_ratio = f32(0.1)
const ship_acceleration_response = f32(0.015)
const ship_deceleration_response = f32(0.05)
const ship_bank_response = f32(0.1)
const ship_bank_retention = f32(0.9)
const ship_turn_rate = f32(0.08)
const camera_angle_response = f32(0.1)
const overdrive_target_response = f32(0.001)
const speed_target_rise_response = f32(0.005)
const speed_target_fall_response = f32(0.03)
const ship_base_sight_depth = f32(35)
// Forward/back travel in course slices, centered around the starting position.
const relative_depth_min = f32(-2.5)
const relative_depth_max = f32(2.5)
const relative_depth_step = f32(0.05)
