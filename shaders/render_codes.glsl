#ifndef TT_RENDER_CODES_GLSL
#define TT_RENDER_CODES_GLSL

// Packed RenderInstance.kind bases; keep in sync with sim/render_codes.v.
const float render_player_kind = 1.0;
const float render_shot_kind = 2.0;
const float render_star_shot_kind = 2.25;
const float render_enemy_kind = 3.0;
const float render_boss_bit_kind = 4.6;
const float render_charged_shot_kind = 5.0;
const float render_particle_kind = 6.0;
const float render_bullet_kind = 7.0;
const float render_multiplier_kind = 20.0;

// Decoder boundaries include payload ranges and gaps between object families.
// They are intentionally distinct from the exact base values above.
const float render_player_lower_bound = .5;
const float render_player_upper_bound = 1.5;
const float render_shot_upper_bound = 2.5;
const float render_star_shot_color_threshold = 2.2;
const float render_enemy_upper_bound = 3.5;
const float render_boss_bit_lower_bound = 4.5;
const float render_boss_bit_upper_bound = 4.9;
const float render_charged_shot_upper_bound = 5.5;
const float render_particle_star_kind = 6.5;
const float render_particle_fragment_kind = 6.75;
const float render_multiplier_lower_bound = 19.5;
const float render_multiplier_upper_bound = 30.0;
const float render_tunnel_lower_bound = 62.5;

// CourseVertex.brightness packs a line family plus brightness in [0, 1].
// These bases match sim/course.v.
const float course_normal_ring_brightness_base = 2.0;
const float course_final_ring_brightness_base = 4.0;
const float course_side_light_brightness_base = 6.0;

#endif
