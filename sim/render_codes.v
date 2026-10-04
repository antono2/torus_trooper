module sim

// RenderInstance.kind is a packed wire format, not a gameplay tuning value.
// Each base identifies an object family; the fractional part carries size,
// shape, damage, or particle data. Matching GLSL constants live in
// shaders/render_codes.glsl and are checked by test_build_tools.py.
const render_player_kind = f32(1.0)
const render_shot_kind = f32(2.0)
const render_star_shot_kind = f32(2.25)
const render_enemy_kind = f32(3.0)
const render_boss_bit_kind = f32(4.6)
const render_charged_shot_kind = f32(5.0)
const render_particle_kind = f32(6.0)
const render_bullet_kind = f32(7.0)
const render_multiplier_kind = f32(20.0)
