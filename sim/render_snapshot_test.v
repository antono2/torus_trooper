// Checks render layouts, orientation order, course fades, and snapshot consistency.
module sim

import math

fn new_visible_render_simulation() Simulation {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.ship.lifecycle_counter = 0
	simulation.ship.invulnerable_ticks = 0
	return simulation
}

fn test_render_instance_has_opencl_friendly_contiguous_float_layout() {
	assert sizeof(RenderInstance) == 64
	assert sizeof(CourseVertex) == 16
	assert sizeof(CourseFillVertex) == 28
}

fn test_render_orientation_multiplication_preserves_source_call_order() {
	quarter_turn := f32(math.pi / 2)
	combined := render_y_rotation(quarter_turn).multiply(render_z_rotation(quarter_turn))
	assert math.abs(combined.x - 0.5) < 0.0001
	assert math.abs(combined.y - 0.5) < 0.0001
	assert math.abs(combined.z - 0.5) < 0.0001
	assert math.abs(combined.w - 0.5) < 0.0001
}

fn test_ship_bank_rotation_preserves_source_flight_axis() {
	bank := render_z_rotation(-0.8)
	// ShipShape's long dimension is source Z. Banking may rotate its lateral
	// and radial axes, but must leave the longitudinal flight vector unchanged.
	assert bank.x == 0
	assert bank.y == 0
	assert math.abs(bank.z + f32(math.sin(0.4))) < 0.0001
	assert math.abs(bank.w - f32(math.cos(0.4))) < 0.0001
}

fn test_course_fill_snapshot_uses_relative_panel_horizon_alpha_recurrence() {
	mut simulation := new_visible_render_simulation()
	simulation.palette_transition_ticks = 0
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	vertices := simulation.render_course_fill_snapshot(72, 32, 0)
	assert vertices.len == 54 * 32 * 6
	assert vertices[0].r == 0.7
	assert vertices[0].g == 0.9
	assert vertices[0].b == 1
	assert vertices[0].a > 0
	assert vertices[0].a < 0.05
	assert vertices[0].a < vertices.last().a
	assert vertices[0].a == vertices[1].a
	assert vertices[2].a > vertices[0].a
	mut changed := vertices.clone()
	changed[0] = CourseFillVertex{ ...changed[0], a: changed[0].a + 0.01 }
	assert course_fill_snapshot_checksum(changed) != course_fill_snapshot_checksum(vertices)
}

fn test_course_panel_far_edge_fades_in_across_several_rows() {
	brightness := tunnel_poly_brightness(22, 22)
	assert brightness[21] == 0
	assert brightness[20] > 0 && brightness[20] < 0.05
	assert brightness[19] > brightness[20]
	assert brightness[18] > brightness[19]
	assert brightness[17] > brightness[18]
	assert brightness[16] > 0.2
	long_brightness := tunnel_poly_brightness(72, 54)
	assert long_brightness[53] == 0
	assert long_brightness[52] > 0 && long_brightness[52] < 0.05
	assert long_brightness[51] > long_brightness[52]
}

fn test_new_panel_emerges_gradually_through_fixed_far_plane() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	camera_distance := simulation.course_camera_distance(0, false)
	simulation.ship.course_position = 0.1
	early_start := simulation.course_render_start_for_camera(0, false, 1)
	early := simulation.render_course_fill_snapshot_from_with_rear_blend(22, 8, 0,
		early_start, camera_distance, 0, 20)
	simulation.ship.course_position = 0.9
	late_start := simulation.course_render_start_for_camera(0, false, 1)
	late := simulation.render_course_fill_snapshot_from_with_rear_blend(22, 8, 0,
		late_start, camera_distance, 0, 20)
	assert early.len == late.len
	assert early[0].a == 0
	assert late[0].a == 0
	assert late[2].a > early[2].a
	assert late[2].a > 0
}

fn test_far_panel_opacity_stays_continuous_when_its_row_wraps() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	simulation.ship.course_position = 0.999
	before := simulation.render_course_fill_snapshot(72, 8, 0)
	simulation.ship.course_position = 1.001
	after := simulation.render_course_fill_snapshot(72, 8, 0)
	// The same distant panel shifts from the farthest emitted row to the next
	// row when the fractional course position wraps.
	before_panel := before[2]
	after_panel := after[8 * 6 + 2]
	assert math.abs(before_panel.z - after_panel.z) < 0.0012
	assert math.abs(before_panel.a - after_panel.a) < 0.0002
}

fn test_configurable_panel_horizon_draws_more_solid_course_before_wiremesh() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	short := simulation.render_course_fill_snapshot_from_with_rear_blend(72, 32, 0, 0, course_render_camera_distance, 0, 54)
	long := simulation.render_course_fill_snapshot_from_with_rear_blend(72, 32, 0, 0, course_render_camera_distance, 0, 70)
	assert long.len > short.len
	assert short.len == 54 * 32 * 6
	assert long.len == 70 * 32 * 6
}

fn test_panel_horizon_accepts_wire_only_and_999_rows() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	wire_only := simulation.render_course_fill_snapshot_from_with_rear_blend(72, 32, 0, 0, course_render_camera_distance, 0, 0)
	maximum := simulation.render_course_fill_snapshot_from_with_rear_blend(1001, 32, 0, 0, course_render_camera_distance, 0, 999)
	assert wire_only.len == 0
	assert maximum.len == 999 * 32 * 6
}

fn test_wiremesh_stays_dense_through_configured_panel_horizon() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	vertices := simulation.render_course_snapshot_from_with_panel_horizon(80, 32, 0, 0, 64)
	// Ring edges are emitted first, two vertices for every angular segment.
	for ring in 1 .. 66 {
		previous_z := vertices[(ring - 1) * 32 * 2].z
		current_z := vertices[ring * 32 * 2].z
		assert math.abs(current_z - previous_z - course_render_depth_scale) < 0.00001
	}
}

fn test_wire_and_panel_horizons_are_independent_depth_planes() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	// A short wire horizon must not shorten the solid panels.
	wire := simulation.render_course_snapshot_from_with_draw_distance(6, 8, 0, 0, 12,
		course_render_camera_distance, 0)
	panels := simulation.render_course_fill_snapshot_from_with_rear_blend(14, 8, 0, 0,
		course_render_camera_distance, 0, 12)
	assert math.abs(wire[5 * 8 * 2].z - (course_render_depth_base + 5 * course_render_depth_scale)) < 0.00001
	assert panels.len == 12 * 8 * 6
	assert simulation.render_course_fill_snapshot_from_with_rear_blend(3, 8, 0, 0,
		course_render_camera_distance, 0, 1).len == 8 * 6
	// With panels disabled, a longer wire horizon still renders.
	long_wire := simulation.render_course_snapshot_from_with_draw_distance(21, 8, 0, 0,
		0, course_render_camera_distance, 0)
	assert math.abs(long_wire[20 * 8 * 2].z - (course_render_depth_base + 20 * course_render_depth_scale)) < 0.00001
	assert simulation.render_course_fill_snapshot_from_with_rear_blend(4, 8, 0, 0,
		course_render_camera_distance, 0, 0).len == 0
}

fn test_configurable_panel_horizon_ends_on_one_depth_plane() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.08, turn_y: -0.05 }]
	}
	vertices := simulation.render_course_fill_snapshot_from_with_rear_blend(72, 32, 0.4, 0, course_render_camera_distance, 0, 64)
	assert vertices.len == 64 * 32 * 6
	far_plane := vertices[0].z
	for segment in 0 .. 32 {
		base := segment * 6
		assert math.abs(vertices[base].z - far_plane) < 0.000001
		assert math.abs(vertices[base + 1].z - far_plane) < 0.000001
		assert math.abs(vertices[base + 3].z - far_plane) < 0.000001
	}
}

fn test_open_course_fill_only_covers_playable_angular_segments() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 1, right: 2, rad: 21 }]
	}
	full_count := simulation.render_course_fill_snapshot(8, 32, 0).len
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	assert full_count > 0
	assert full_count < simulation.render_course_fill_snapshot(8, 32, 0).len
}

fn test_course_surface_uses_the_same_angle_convention_as_ship_collision() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	forward := simulation.render_course_snapshot(8, 8, 0)
	backward := simulation.render_course_backward_snapshot(8, 8, 0)
	assert math.abs(forward[0].x) < 0.00001
	assert forward[0].y > 1.34
	assert math.abs(backward[0].x) < 0.00001
	assert backward[0].y > 1.34
}

fn test_course_fill_clips_non_wrapping_edges_to_collision_angles() {
	slice := CourseSlice{ left: 0.07, right: 1.03, rad: 21 }
	first := playable_course_angle_spans(0, f32(math.pi / 4), slice)
	second := playable_course_angle_spans(f32(math.pi / 4), f32(math.pi / 2), slice)
	assert first.len == 1
	assert first[0].start == slice.left
	assert first[0].end == f32(math.pi / 4)
	assert second.len == 1
	assert second[0].start == f32(math.pi / 4)
	assert second[0].end == slice.right
}

fn test_course_fill_clips_wrapping_edges_to_collision_angles() {
	slice := CourseSlice{ left: 5.8, right: 0.3, rad: 21 }
	low := playable_course_angle_spans(0, 0.5, slice)
	high := playable_course_angle_spans(5.5, f32(math.pi * 2), slice)
	assert low == [CourseAngleSpan{ start: 0, end: slice.right }]
	assert high == [CourseAngleSpan{ start: slice.left, end: f32(math.pi * 2) }]
}

fn test_backward_course_snapshot_extends_behind_the_current_slice() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	forward := simulation.render_course_snapshot(8, 8, 0)
	backward := simulation.render_course_backward_snapshot(8, 8, 0)
	assert forward.len == 240
	assert backward.len == forward.len
	assert forward[16].z > forward[0].z
	assert backward[16].z < backward[0].z
	backward_fill := simulation.render_course_backward_fill_snapshot(8, 8, 0)
	assert backward_fill.len == 6 * 8 * 6
	assert backward_fill[0].z < course_render_depth_base
}

fn test_backward_course_snapshot_progresses_across_sub_f32_boundary_step() {
	mut simulation := new_visible_render_simulation()
	// This is the title replay position that previously froze while building a
	// distant rear ring: the boundary step is half an f32 ULP at distance -64.
	simulation.ship.course_position = 0.0000792
	frame := CourseRenderFrame{
		distance: -64.0000763
	}
	target := f32(-64.3493576)
	advanced := simulation.advance_course_frame(frame, target)
	assert advanced.distance == target
	assert !math.is_nan(advanced.center_x)
	assert !math.is_nan(advanced.center_y)
}

fn test_course_panels_follow_fractional_ship_travel() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	simulation.ship.course_position = 0.25
	first := simulation.render_course_snapshot(8, 8, 0)
	simulation.ship.course_position = 0.75
	second := simulation.render_course_snapshot(8, 8, 0)
	assert math.abs((first[0].z - second[0].z) - 0.275) < 0.00001
	simulation.ship.course_position = 1
	wrapped := simulation.render_course_snapshot(8, 8, 0)
	expected_backtrack := -course_render_camera_distance + course_render_rear_margin
	assert math.abs(wrapped[0].z - (course_render_depth_base - expected_backtrack * course_render_depth_scale)) < 0.00001
}

fn test_course_rear_ring_is_retained_behind_the_camera_plane() {
	assert course_render_rear_margin > 1
	for position in [f32(0), 0.25, 0.999, 12.4] {
		start := course_render_start_distance(position)
		assert start <= course_render_camera_distance - course_render_rear_margin
		// Even the forward edge of the oldest complete tile remains at least the
		// extra half-tile guard behind the camera plane.
		assert start + 1 <= course_render_camera_distance - (course_render_rear_margin - 1)
		assert course_render_depth_base + start * course_render_depth_scale < 0
	}
}

fn test_course_mesh_seam_tracks_actual_camera_and_stays_behind_its_view() {
	mut simulation := new_visible_render_simulation()
	simulation.ship.course_position = 12.25
	forward_camera_distance := course_render_camera_distance + 20
	forward_start := simulation.course_render_start_for_camera(20, true, 1)
	assert forward_start <= forward_camera_distance - course_render_rear_margin
	assert forward_start > forward_camera_distance - course_render_rear_margin - 1.01
	backward_start := simulation.course_render_start_for_camera(20, true, -1)
	assert backward_start >= forward_camera_distance + course_render_rear_margin
	assert backward_start < forward_camera_distance + course_render_rear_margin + 1.01
	// Mesh rows stay on a stable half-slice lattice. A row can be recycled only
	// after the guarded seam is already behind the camera.
	forward_lattice := simulation.ship.course_position + forward_start - 0.5
	backward_lattice := simulation.ship.course_position + backward_start - 0.5
	assert math.abs(forward_lattice - f32(math.round(forward_lattice))) < 0.0001
	assert math.abs(backward_lattice - f32(math.round(backward_lattice))) < 0.0001
	gameplay_start := simulation.course_render_start_for_camera(0, false, 1)
	assert gameplay_start == course_render_start_distance(simulation.ship.course_position)
}

fn test_course_panel_behind_ship_survives_fractional_wrap() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.02, turn_y: -0.01 }]
	}
	simulation.ship.course_position = 0.999
	before := simulation.render_course_snapshot(12, 8, 0)
	simulation.ship.course_position = 1.001
	after := simulation.render_course_snapshot(12, 8, 0)
	// The same boundary crosses the ship plane while shifting from ring 6 to
	// ring 5; it must not disappear with the discarded oldest rear ring.
	assert math.abs(before[96].z - after[80].z) < 0.0012
	assert math.abs(before[96].x - after[80].x) < 0.0012
	assert math.abs(before[96].y - after[80].y) < 0.0012
	assert math.abs(before[96].brightness - after[80].brightness) < 0.0001
	assert before[80].z < course_render_depth_base
	assert after[80].z < course_render_depth_base
}

fn test_course_panel_fill_style_survives_fractional_wrap() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	simulation.ship.course_position = 0.999
	before := simulation.render_course_fill_snapshot(16, 8, 0)
	simulation.ship.course_position = 1.001
	after := simulation.render_course_fill_snapshot(16, 8, 0)
	// The panel at row 6 moves to row 5 when its predecessor passes the
	// camera. Both its geometry and opacity must remain continuous.
	before_panel := before[48]
	after_panel := after[96]
	assert math.abs(before_panel.x - after_panel.x) < 0.0012
	assert math.abs(before_panel.y - after_panel.y) < 0.0012
	assert math.abs(before_panel.z - after_panel.z) < 0.0012
	assert math.abs(before_panel.a - after_panel.a) < 0.0002
}

fn test_ship_surface_radius_follows_current_course_slice() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }, CourseSlice{ full: true, rad: 14 }]
	}
	assert math.abs(simulation.ship_surface_radius() - course_render_radius / source_tunnel_radius_ratio) < 0.00001
	simulation.ship.relative_depth = 1
	assert math.abs(simulation.ship_surface_radius() - course_render_radius * 14 / 21 / source_tunnel_radius_ratio) < 0.00001
	ship := simulation.render_instances()[0]
	assert math.abs(ship.depth - (simulation.ship.relative_depth + ship_render_depth_offset)) < 0.00001
	assert math.abs(simulation.ship_render_depth() - ship.depth) < 0.00001
	_, expected_radius := simulation.actor_surface_placement_with_offset(simulation.ship.angle, simulation.ship.relative_depth + ship_render_depth_offset, simulation.camera_angle(), -ship_render_surface_clearance)
	assert math.abs(simulation.ship_render_surface_radius(simulation.camera_angle()) - expected_radius) < 0.00001
}

fn test_backward_course_snapshot_includes_a_gate_behind_the_ship() {
	mut simulation := new_visible_render_simulation()
	simulation.ship.course_position = 10
	simulation.course = CourseProfile{
		slices: []CourseSlice{len: 20, init: CourseSlice{ full: true, rad: 21 }}
		rings:  [CourseRing{ index: 8 }]
	}
	forward := simulation.render_course_snapshot(8, 8, 0)
	backward := simulation.render_course_backward_snapshot(8, 8, 0)
	assert forward.len == 240
	assert backward.len == forward.len + 16 * 8
}

fn test_enemy_render_kind_carries_a_deterministic_shape_seed_inside_each_tier() {
	assert enemy_render_kind(0, 12_345) == enemy_render_kind(0, 12_345)
	assert enemy_render_kind(0, 100) != enemy_render_kind(0, 90_000)
	assert enemy_render_kind(1, 100) != enemy_render_kind(1, 90_000)
	assert enemy_render_kind(2, 100) != enemy_render_kind(2, 90_000)
	assert enemy_render_kind(0, 99_998) >= 3.0
	assert enemy_render_kind(0, 99_998) < 3.125
	assert enemy_render_kind(1, 99_998) >= 3.125
	assert enemy_render_kind(1, 99_998) < 3.25
	assert enemy_render_kind(2, 99_998) >= 3.25
	assert enemy_render_kind(2, 99_998) < 3.5
}

fn test_enemy_render_kind_losslessly_round_trips_all_source_seeds_and_damage_states() {
	for tier in 0 .. 3 {
		for seed in 0 .. 99_999 {
			for damaged in [false, true] {
				encoded := enemy_render_kind_with_damage(tier, seed, damaged)
				decoded := decode_enemy_render_kind(encoded)
				assert decoded == EnemyRenderCode{
					tier:    tier
					seed:    seed
					damaged: damaged
				}
			}
		}
	}
}

fn test_render_snapshot_uses_the_selected_enemy_specs_shape_seed() {
	mut simulation := new_visible_render_simulation()
	simulation.zone_specs = ZoneEnemySpecs{
		middle: [EnemySpec{ shape_seed: 100 }, EnemySpec{ shape_seed: 90_000 }]
	}
	simulation.enemies[0] = Enemy{ alive: true, kind: 1, spec_index: 0 }
	simulation.enemies[1] = Enemy{ alive: true, kind: 1, spec_index: 1 }
	instances := simulation.render_instances()
	assert instances.len == 3
	assert instances[1].kind == enemy_render_kind(1, 100)
	assert instances[2].kind == enemy_render_kind(1, 90_000)
	assert instances[1].kind != instances[2].kind
}

fn test_damaged_enemy_flashes_without_changing_its_seeded_shape() {
	mut simulation := new_visible_render_simulation()
	simulation.zone_specs = ZoneEnemySpecs{
		middle: [EnemySpec{ shape_seed: 12_345 }]
	}
	simulation.enemies[0] = Enemy{ alive: true, kind: 1, damaged: true }
	instance := simulation.render_instances()[1]
	assert decode_enemy_render_kind(instance.kind) == EnemyRenderCode{
		tier:    1
		seed:    12_345
		damaged: true
	}
}

fn test_particle_render_kind_packs_life_and_fragment_tier_inside_its_kind_range() {
	small := particle_render_kind(Particle{
		life:         21
		initial_life: 42
		kind:         .fragment
	})
	boss := particle_render_kind(Particle{
		life:         21
		initial_life: 42
		kind:         .fragment
		visual_tier:  2
	})
	assert boss > small
	assert small >= 6.75 && small < 7.0
	assert boss >= 6.75 && boss < 7.0
}

fn test_particle_render_kind_packs_height_and_luminosity_in_float4_kind() {
	base := Particle{
		life:         20
		initial_life: 40
		kind:         .spark
		height:       1
		luminosity:   0.8
	}
	assert particle_render_kind(base) != particle_render_kind(Particle{
		...base
		height: -20
	})
	assert particle_render_kind(base) != particle_render_kind(Particle{
		...base
		luminosity: 0.4
	})
}

fn test_fragment_payload_carries_dual_rotation_and_source_dimensions() {
	particle := Particle{
		kind:            .fragment
		spin:            1.2
		secondary_spin:  -0.7
		fragment_width:  3.25
		fragment_height: 9.5
		scale:           0.8
	}
	payload := particle_fragment_payload(particle)
	assert payload <= 16_777_215
	decoded := decode_particle_fragment_payload(payload)
	assert decoded.spin_bin == particle_fragment_angle_bin(particle.spin)
	assert decoded.secondary_spin_bin == particle_fragment_angle_bin(particle.secondary_spin)
	assert decoded.width_bin > 35
	assert decoded.width_bin < 38
	assert decoded.height_bin > 33
	assert decoded.height_bin < 36
	assert particle_render_heading(particle, false) == f32(payload)
}

fn test_jet_mesh_faces_opposite_its_trail_velocity() {
	backward_jet := Particle{
		kind:     .jet
		velocity: Vec2{ y: -0.2 }
	}
	assert f32(math.abs(particle_render_heading(backward_jet, false))) < 0.0001
	assert f32(math.abs(particle_render_heading(backward_jet, true) - particle_reflection_heading_offset)) < 0.0001

	sideways_jet := Particle{
		kind:     .jet
		velocity: Vec2{ x: 0.2 }
	}
	assert wrapped_distance(particle_render_heading(sideways_jet, false), -f32(math.pi / 2)) < 0.0001
}

fn test_in_course_sparks_and_jets_emit_dim_tunnel_reflections() {
	mut simulation := new_visible_render_simulation()
	simulation.particles[0] = Particle{
		alive:        true
		position:     Vec2{ x: 0.4, y: 8 }
		velocity:     Vec2{ x: 0.1, y: -0.2 }
		life:         12
		initial_life: 16
		kind:         .spark
		height:       1.5
		in_course:    true
		luminosity:   0.9
	}
	instances := simulation.render_instances()
	assert instances.len == 3
	assert instances[1].depth == instances[2].depth
	assert instances[1].kind != instances[2].kind
	actual_angle, actual_radius := simulation.actor_surface_placement_with_offset(0.4, 8, simulation.camera_angle(), -1.5 * course_render_height_scale)
	reflection_angle, reflection_radius := simulation.actor_surface_placement_with_offset(0.4, 8, simulation.camera_angle(), 1.5 * course_render_height_scale)
	assert math.abs(instances[1].angle - actual_angle) < 0.0001
	assert math.abs(instances[2].angle - reflection_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - actual_radius) < 0.0001
	assert math.abs(instances[2].surface_radius - reflection_radius) < 0.0001
	assert particle_render_kind(Particle{
		...simulation.particles[0]
		height: -1.5
	}) == instances[2].kind
}

fn test_player_jets_share_the_shifted_ship_plane_and_clear_its_surface() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: 0.04, turn_y: -0.02 }]
	}
	simulation.ship.relative_depth = 1.2
	simulation.ship.speed = 0.7
	jet := Particle{
		alive:        true
		// State after the same-frame particle update that follows spawning.
		position:     Vec2{ x: 1.1, y: 1.2 - 0.15 - 0.7 - 0.2 }
		velocity:     Vec2{ y: -0.2 }
		life:         12
		initial_life: 16
		kind:         .jet
		height:       1
		in_course:    true
	}
	simulation.particles[0] = jet
	instances := simulation.render_instances_for_camera(0.7)
	assert instances.len == 3
	expected_depth := simulation.ship.relative_depth - 0.15 + ship_render_depth_offset - ship_exhaust_render_depth_clearance
	assert math.abs(simulation.particle_course_depth(jet) - expected_depth) < 0.0001
	assert expected_depth < simulation.ship.relative_depth + ship_render_depth_offset
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(jet.position.x, expected_depth, 0.7, -ship_render_surface_clearance - course_render_height_scale)
	assert math.abs(instances[1].depth - expected_depth) < 0.0001
	assert math.abs(instances[1].angle - expected_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - expected_radius) < 0.0001
}

fn test_out_of_course_spark_stays_on_tunnel_without_emitting_reflection() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [
			CourseSlice{ left: 1, right: 2, rad: 18, turn_x: 0.05, turn_y: -0.04 },
		]
	}
	simulation.particles[0] = Particle{
		alive:        true
		position:     Vec2{ x: 0.4, y: 8 }
		life:         5
		initial_life: 10
		kind:         .spark
		height:       1
		in_course:    false
	}
	simulation.particles[1] = Particle{
		alive:        true
		life:         5
		initial_life: 10
		kind:         .fragment
		in_course:    true
	}
	instances := simulation.render_instances_for_camera(0.7)
	assert instances.len == 3
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(0.4, 8, 0.7, -course_render_height_scale)
	assert math.abs(instances[1].angle - expected_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - expected_radius) < 0.0001
}

fn test_render_snapshot_applies_expected_seven_degree_shot_spin() {
	mut simulation := new_visible_render_simulation()
	simulation.shots[0] = Shot{ alive: true, age: 10, direction: 0.2 }
	instances := simulation.render_instances()
	assert instances.len == 2
	shot := instances[1]
	expected := render_axis_rotation(0, 1, 10, 0.2).multiply(render_z_rotation(f32(math.pi) * 70 / 180))
	assert math.abs(shot.heading - 0.2) < 0.0001
	assert math.abs(shot.rotation_x - expected.x) < 0.0001
	assert math.abs(shot.rotation_y - expected.y) < 0.0001
	assert math.abs(shot.rotation_z - expected.z) < 0.0001
	assert math.abs(shot.rotation_w - expected.w) < 0.0001
}

fn test_enemy_bullet_keeps_direction_and_axial_spin_as_ordered_rotations() {
	mut simulation := new_visible_render_simulation()
	simulation.bullets[0] = Bullet{
		alive:     true
		age:       15
		direction: 0.3
		x_reverse: -1
	}
	bullet := simulation.render_instances()[1]
	expected := render_y_rotation(-0.3).multiply(render_z_rotation(f32(math.pi) / 2))
	assert math.abs(bullet.heading + 0.3) < 0.0001
	assert math.abs(bullet.rotation_x - expected.x) < 0.0001
	assert math.abs(bullet.rotation_y - expected.y) < 0.0001
	assert math.abs(bullet.rotation_z - expected.z) < 0.0001
	assert math.abs(bullet.rotation_w - expected.w) < 0.0001
}

fn test_player_shots_follow_the_generated_course_surface() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: 0.05, turn_y: -0.04 }]
	}
	simulation.shots[0] = Shot{
		alive:    true
		position: Vec2{ x: 1.2, y: 8 }
		charged:  true
		size:     8
	}
	instances := simulation.render_instances_for_camera(0.7)
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(1.2, 8, 0.7, -0.09)
	assert math.abs(instances[1].angle - expected_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - expected_radius) < 0.0001
}

fn test_render_snapshot_encodes_floating_multiplier_and_alpha() {
	mut simulation := new_visible_render_simulation()
	simulation.multiplier_popups[0] = MultiplierPopup{
		alive:       true
		position:    Vec2{ x: 0.25, y: 5 }
		alpha:       0.77
		multiplier:  12
		large_label: true
	}
	instances := simulation.render_instances_for_camera(0.4)
	assert instances.len == 2
	assert instances[1].angle == 0
	assert instances[1].depth == 0
	assert multiplier_render_slot(instances[1].kind) == 0
	assert int(instances[1].heading) == 140
	assert instances[1].heading > 140.76 && instances[1].heading < 140.78
}

fn test_multiplier_popups_render_newest_first_in_unique_scrolling_list_slots() {
	mut simulation := new_visible_render_simulation()
	simulation.multiplier_popup_cursor = 14
	simulation.multiplier_popups[14] = MultiplierPopup{
		alive:      true
		alpha:      0.8
		multiplier: 4
	}
	simulation.multiplier_popups[15] = MultiplierPopup{
		alive:      true
		alpha:      0.7
		multiplier: 3
	}
	simulation.multiplier_popups[0] = MultiplierPopup{
		alive:      true
		alpha:      0.6
		multiplier: 2
	}
	instances := simulation.render_instances()
	assert instances.len == 4
	assert int(instances[1].heading) == 4
	assert multiplier_render_slot(instances[1].kind) == 0
	assert int(instances[2].heading) == 3
	assert multiplier_render_slot(instances[2].kind) == 1
	assert int(instances[3].heading) == 2
	assert multiplier_render_slot(instances[3].kind) == 2
}

fn test_multiplier_popup_payload_preserves_source_bullet_and_enemy_label_sizes() {
	small := multiplier_popup_payload(MultiplierPopup{
		multiplier: 2
		alpha:      0.8
	})
	large := multiplier_popup_payload(MultiplierPopup{
		multiplier:  2
		alpha:       0.8
		large_label: true
	})
	assert small > 2.79 && small < 2.81
	assert large == small + multiplier_large_label_offset
}

fn test_render_snapshot_applies_bullet_spin_and_wire_disappearance_encoding() {
	mut simulation := new_visible_render_simulation()
	simulation.bullets[0] = Bullet{
		alive:        true
		age:          10
		direction:    0.2
		visual_shape: 2
	}
	live := simulation.render_instances()
	assert live.len == 2
	assert live[1].kind == 9
	live_heading := live[1].heading
	assert live_heading > 0.19 && live_heading < 0.21
	expected_spin := render_y_rotation(0.2).multiply(render_z_rotation(f32(math.pi) / 3))
	assert math.abs(live[1].rotation_z - expected_spin.z) < 0.0001
	simulation.bullets[0].x_reverse = f32(-1)
	mirrored := simulation.render_instances()
	mirrored_heading := mirrored[1].heading
	assert mirrored_heading > -0.21 && mirrored_heading < -0.19
	simulation.bullets[0].start_disappearing()
	disappearing := simulation.render_instances()
	assert disappearing.len == 2
	assert disappearing[1].kind > 10
	assert disappearing[1].kind < 10.49
}

fn test_enemy_bullets_follow_the_generated_course_surface() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 16, turn_x: 0.06, turn_y: -0.035 }]
	}
	simulation.bullets[0] = Bullet{
		alive:        true
		position:     Vec2{ x: 2.1, y: 9 }
		direction:    0.35
		visual_shape: 4
		visual_scale: 1.2
	}
	instances := simulation.render_instances_for_camera(0.8)
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(2.1, 9, 0.8, -0.06 * 1.2)
	assert math.abs(instances[1].angle - expected_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - expected_radius) < 0.0001
	assert math.abs(instances[1].heading - 0.35) < 0.001
}

fn test_render_snapshot_encodes_boss_bullet_scale_during_live_and_wire_phases() {
	mut simulation := new_visible_render_simulation()
	simulation.bullets[0] = Bullet{
		alive:        true
		visual_shape: 2
		visual_scale: 1.2
	}
	live := simulation.render_instances()
	assert live[1].kind == 9.5
	simulation.bullets[0].start_disappearing()
	disappearing := simulation.render_instances()
	assert disappearing[1].kind > 10.5
	assert disappearing[1].kind < 10.99
}

fn test_course_snapshot_checksum_detects_geometry_changes() {
	simulation := new_simulation(SimulationConfig{
		procedural_course: true
	})
	mut vertices := simulation.render_course_snapshot(4, 8, simulation.camera_angle())
	assert vertices.len == 112
	checksum := course_snapshot_checksum(vertices)
	vertices[0] = CourseVertex{ ...vertices[0], x: vertices[0].x + 0.01 }
	assert course_snapshot_checksum(vertices) != checksum
}

fn test_course_snapshot_uses_source_depth_growth_and_seeded_gate_geometry() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
		rings:  [CourseRing{ index: 5, is_final: true }]
	}
	vertices := simulation.render_course_snapshot(72, 32, 0)
	base_vertex_count := (72 * 32 + 71 * 32) * 2
	assert vertices.len == base_vertex_count + 14 * 8 * 2
	assert vertices[base_vertex_count].brightness >= course_final_ring_brightness_base
	assert vertices[base_vertex_count].z > 4.94
	assert vertices[base_vertex_count].z < 4.96
	assert vertices[base_vertex_count - 1].z > 500
}

fn test_normal_course_gate_uses_sixteen_source_quadrilateral_segments() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
		rings:  [CourseRing{ index: 5 }]
	}
	vertices := simulation.render_course_snapshot(72, 32, 0)
	base_vertex_count := (72 * 32 + 71 * 32) * 2
	assert vertices.len == base_vertex_count + 16 * 8
	assert vertices[base_vertex_count].brightness >= course_normal_ring_brightness_base
	assert vertices[base_vertex_count].brightness < course_final_ring_brightness_base
}

fn test_open_course_slices_add_relative_range_side_light_outlines() {
	mut simulation := new_visible_render_simulation()
	simulation.palette_transition_ticks = 0
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 1, right: 2, rad: 21 }]
	}
	vertices := simulation.render_course_snapshot(4, 8, 0)
	base_vertex_count := (4 * 8 + 3 * 8) * 2
	// Boundary markers use three of four rings, extending beyond the one-panel
	// horizon at this deliberately small snapshot size.
	assert vertices.len == base_vertex_count + 3 * 2 * 8
	for vertex in vertices[base_vertex_count..] {
		assert vertex.brightness >= course_side_light_brightness_base
	}
	first_light_left := vertices[base_vertex_count].x
	first_light_right := vertices[base_vertex_count + 1].x
	assert first_light_right > first_light_left
}

fn test_open_course_boundary_markers_extend_beyond_solid_panels() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 1, right: 2, rad: 21 }]
	}
	lines := simulation.render_course_snapshot(72, 8, 0)
	base_vertex_count := (72 * 8 + 71 * 8) * 2
	markers := lines[base_vertex_count..]
	fills := simulation.render_course_fill_snapshot(72, 8, 0)
	mut farthest_marker := f32(-1000)
	for marker in markers {
		farthest_marker = f32_max(farthest_marker, marker.z)
	}
	mut farthest_panel := f32(-1000)
	for panel in fills {
		farthest_panel = f32_max(farthest_panel, panel.z)
	}
	assert markers.len > 0
	assert fills.len > 0
	assert farthest_marker > farthest_panel
}

fn test_boundary_markers_reach_longest_independent_draw_horizon() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 1, right: 2, rad: 21 }]
	}
	start := f32(3)
	forward := simulation.render_course_side_lights_to_distance(0, start, 1, 2, 5)
	assert forward.len == 4 * 2 * 8
	mut farthest_forward := f32(-1000)
	for vertex in forward {
		farthest_forward = f32_max(farthest_forward, vertex.z)
	}
	assert math.abs(farthest_forward - (course_render_depth_base + (start + 5) * course_render_depth_scale)) < 0.001
	backward := simulation.render_course_side_lights_to_distance(0, start, -1, 2, 5)
	assert backward.len == forward.len
	mut farthest_backward := f32(1000)
	for vertex in backward {
		farthest_backward = f32_min(farthest_backward, vertex.z)
	}
	assert math.abs(farthest_backward - (course_render_depth_base + (start - 5) * course_render_depth_scale)) < 0.001
}

fn test_full_circle_boundary_markers_remain_visible_across_row_recycling() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21 }]
	}
	simulation.ship.course_position = 0.999
	before_start := simulation.course_render_start_for_camera(0, false, 1)
	before := simulation.render_course_side_lights_to_distance(0, before_start, 1, 0,
		32)
	simulation.ship.course_position = 1.001
	after_start := simulation.course_render_start_for_camera(0, false, 1)
	after := simulation.render_course_side_lights_to_distance(0, after_start, 1, 0, 32)
	assert before.len > 0
	assert after.len > 0
	mut nearest_before := f32(1000)
	mut nearest_after := f32(1000)
	for vertex in before {
		assert vertex.brightness >= course_side_light_brightness_base
		if vertex.z > 0 && vertex.z < nearest_before {
			nearest_before = vertex.z
		}
	}
	for vertex in after {
		if vertex.z > 0 && vertex.z < nearest_after {
			nearest_after = vertex.z
		}
	}
	assert math.abs(nearest_before - nearest_after) < 0.01
}

fn test_render_snapshot_and_flatten_include_live_actor_classes() {
	mut simulation := new_visible_render_simulation()
	simulation.bullets[0] = Bullet{ alive: true, visual_shape: 4 }
	simulation.shots[0] = Shot{ alive: true, star_shell: true }
	simulation.enemies[0] = Enemy{ alive: true, kind: 1 }
	simulation.passed_enemies[0] = Enemy{ alive: true, kind: 0 }
	simulation.particles[0] = Particle{ alive: true, life: 5, initial_life: 10, kind: .fragment }
	simulation.multiplier_popups[0] = MultiplierPopup{ alive: true, alpha: 0.8, multiplier: 2 }
	entities := simulation.render_entity_soa()
	assert entities.valid()
	assert entities.len() == 7
	instances := pack_render_instances(entities)
	assert instances.len == 7
	assert instances[0].kind == 1
	assert instances[1].kind == 11
	assert instances[2].kind > 2.34 && instances[2].kind < 2.36
	assert instances[3].kind == enemy_render_kind(1, 0)
	assert instances[4].kind == enemy_render_kind(0, 0)
	assert instances[5].kind > 6.75
	assert multiplier_render_slot(instances[6].kind) == 0
	mut values := []f32{}
	flatten_render_instances(instances, mut values)
	assert values.len == instances.len * 16
	assert values[2] == instances[0].kind
	assert render_snapshot_checksum(instances) == render_snapshot_checksum(instances)
	mut changed := instances.clone()
	changed[1] = RenderInstance{ ...changed[1], heading: 0.25 }
	assert render_snapshot_checksum(changed) != render_snapshot_checksum(instances)
	changed[1] = RenderInstance{ ...instances[1], rotation_y: 0.25 }
	assert render_snapshot_checksum(changed) != render_snapshot_checksum(instances)
}

fn test_render_snapshot_applies_named_object_scale() {
	mut simulation := new_visible_render_simulation()
	simulation.shots[0] = Shot{ alive: true, size: 1, target_size: 1 }
	instances := simulation.render_instances_for_camera_with_scales(0, RenderScales{
		player:      1.5
		player_shot: 2.25
	})
	assert instances[0].scale == 1.5
	assert instances[1].scale == 2.25
}

fn test_render_snapshot_encodes_source_shot_size() {
	mut simulation := new_visible_render_simulation()
	simulation.shots[0] = Shot{ alive: true, size: 0.5, target_size: 0.5 }
	simulation.shots[1] = Shot{
		alive:       true
		star_shell:  true
		size:        0.5
		target_size: 0.5
	}
	simulation.shots[2] = Shot{
		alive:       true
		charged:     true
		size:        6.8
		target_size: 6.8
	}
	instances := simulation.render_instances()
	assert instances[1].kind > 2.049 && instances[1].kind < 2.051
	assert instances[2].kind > 2.299 && instances[2].kind < 2.301
	assert instances[3].kind > 5.244 && instances[3].kind < 5.246
}

fn test_render_snapshot_uses_expected_ship_invincibility_blink() {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.ship.lifecycle_counter = -268
	assert simulation.render_instances().len == 0
	simulation.ship.lifecycle_counter = -228
	assert simulation.render_instances().len == 0
	simulation.ship.lifecycle_counter = -208
	assert simulation.render_instances().len == 1
	simulation.ship.lifecycle_counter = -192
	assert simulation.render_instances().len == 0
	simulation.ship.lifecycle_counter = 0
	assert simulation.render_instances().len == 1
}

fn test_render_snapshot_orients_live_and_passed_enemies_by_current_bank() {
	mut simulation := new_visible_render_simulation()
	simulation.enemies[0] = Enemy{
		alive:      true
		age:        100
		kind:       1
		base_turn:  0.3
		turn_speed: 0.07
	}
	simulation.passed_enemies[0] = Enemy{
		alive:      true
		age:        50
		kind:       2
		base_turn:  -0.2
		turn_speed: -0.04
	}
	instances := simulation.render_instances()
	live_heading := instances[1].heading
	passed_heading := instances[2].heading
	assert math.abs(live_heading - 0.07) < 0.001
	assert math.abs(passed_heading + 0.04) < 0.001
	_, live_radius := simulation.actor_surface_placement_with_offset(0, 0, simulation.camera_angle(), -enemy_surface_clearance(1))
	_, passed_radius := simulation.actor_surface_placement_with_offset(0, 0, simulation.camera_angle(), -enemy_surface_clearance(2))
	assert math.abs(instances[1].surface_radius - live_radius) < 0.0001
	assert math.abs(instances[2].surface_radius - passed_radius) < 0.0001
	assert instances[1].tangent_radius > 0
	assert instances[2].tangent_radius > 0
	assert instances[1].lateral_radius > 0
	assert instances[2].normal_radius > 0
	assert math.abs(instances[1].rotation_z + f32(math.sin(0.07 / 2))) < 0.0001
	assert math.abs(instances[2].rotation_z + f32(math.sin(-0.04 / 2))) < 0.0001
}

fn test_render_snapshot_uses_expected_boss_bit_y_axis_tumble() {
	mut simulation := new_visible_render_simulation()
	simulation.zone_specs = ZoneEnemySpecs{
		boss: [EnemySpec{
			kind:          2
			bit_count:     1
			bit_formation: .line
			bit_distance:  0.5
		}]
	}
	simulation.enemies[0] = Enemy{
		alive:      true
		kind:       2
		spec_index: 0
		age:        9
		position:   Vec2{ x: 1.2, y: 12 }
	}
	instances := simulation.render_instances()
	assert instances.len == 3
	bit := instances[2]
	expected_rotation := f32(math.pi) * 56 / 180
	assert bit.kind == 4.6
	assert math.abs(bit.heading - expected_rotation) < 0.0001
	assert math.abs(bit.rotation_y - f32(math.sin(expected_rotation / 2))) < 0.0001
	assert math.abs(bit.rotation_w - f32(math.cos(expected_rotation / 2))) < 0.0001
}

fn test_distant_enemy_and_bullet_keep_independent_course_pose_and_heading_precision() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: 0.12, turn_y: -0.08 }]
	}
	simulation.enemies[0] = Enemy{
		alive:      true
		position:   Vec2{ x: 1.2, y: 140 }
		kind:       2
		turn_speed: 0.073
	}
	simulation.bullets[0] = Bullet{
		alive:     true
		position:  Vec2{ x: 2.4, y: 140 }
		direction: -0.057
		x_reverse: 1
	}
	instances := simulation.render_instances_for_camera(0.4)
	assert instances.len == 3
	bullet := instances[1]
	enemy := instances[2]
	assert math.abs(bullet.heading + 0.057) < 0.0001
	assert math.abs(enemy.heading - 0.073) < 0.0001
	bullet_x := -f32(math.sin(f64(bullet.angle - 0.4))) * bullet.surface_radius
	bullet_y := f32(math.cos(f64(bullet.angle - 0.4))) * bullet.surface_radius
	enemy_x := -f32(math.sin(f64(enemy.angle - 0.4))) * enemy.surface_radius
	enemy_y := f32(math.cos(f64(enemy.angle - 0.4))) * enemy.surface_radius
	assert math.sqrt(f64((bullet_x - enemy_x) * (bullet_x - enemy_x) + (bullet_y - enemy_y) * (bullet_y - enemy_y))) > 0.5
	assert bullet.surface_radius > 0
	assert enemy.surface_radius > 0
	assert bullet.tangent_radius > 0
	assert enemy.tangent_radius > 0
	assert bullet.lateral_radius > 0
	assert enemy.normal_radius > 0
}

fn test_enemy_surface_clearance_covers_each_resolution_independent_visual_tier() {
	assert enemy_surface_clearance(0) >= 0.024 * 4.62
	assert enemy_surface_clearance(1) >= 0.056 * 4.62
	assert enemy_surface_clearance(2) >= 0.105 * 4.62
	assert enemy_surface_clearance(2) > enemy_surface_clearance(1)
	assert enemy_surface_clearance(1) > enemy_surface_clearance(0)
}

fn test_background_star_render_placement_tracks_the_outer_course_surface() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: 0.03, turn_y: -0.02 }]
	}
	star := Particle{
		alive:        true
		position:     Vec2{ x: 2.1, y: 9 }
		velocity:     Vec2{ y: -0.4 }
		life:         80
		initial_life: 100
		kind:         .star
		height:       -24
		in_course:    false
	}
	simulation.particles[0] = star
	instances := simulation.render_instances_for_camera(0.6)
	assert instances.len == 2
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(star.position.x, star.position.y, 0.6, -star.height * course_render_height_scale)
	assert math.abs(instances[1].angle - expected_angle) < 0.0001
	assert math.abs(instances[1].surface_radius - expected_radius) < 0.0001
}

fn test_surface_actor_placement_uses_generated_course_bend() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.05, turn_y: -0.03 }]
	}
	camera_angle := f32(0.7)
	angle, radius := simulation.actor_surface_placement(0.4, 3, camera_angle)
	frame := simulation.actor_course_frame_at(3)
	expected_x, expected_y := course_surface_xy(frame, 0.4, camera_angle)
	actual_x := -f32(math.sin(f64(angle - camera_angle))) * radius
	actual_y := f32(math.cos(f64(angle - camera_angle))) * radius
	assert math.abs(actual_x - expected_x) < 0.0001
	assert math.abs(actual_y - expected_y) < 0.0001
}

fn test_surface_actor_render_pose_samples_the_real_adjacent_course_tangent() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: 0.08, turn_y: -0.05 }]
	}
	angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(1.1, 8, 0.4, -0.2)
	expected_angle, expected_radius := simulation.actor_surface_placement_with_offset(1.1, 8, 0.4, -0.2)
	next_angle, next_radius := simulation.actor_surface_placement_with_offset(1.1, 8.5, 0.4, -0.2)
	next_lateral_angle, next_lateral_radius := simulation.actor_surface_placement_with_offset(1.1 + course_orientation_angular_sample, 8, 0.4, -0.2)
	next_normal_angle, next_normal_radius := simulation.actor_surface_placement_with_offset(1.1, 8, 0.4, -0.2 + course_orientation_radial_sample)
	assert math.abs(angle - expected_angle) < 0.0001
	assert math.abs(radius - expected_radius) < 0.0001
	assert math.abs(tangent_radius - next_radius) < 0.0001
	assert wrapped_distance(tangent_angle, next_angle) < 0.0001
	assert math.abs(lateral_radius - next_lateral_radius) < 0.0001
	assert wrapped_distance(lateral_angle, next_lateral_angle) < 0.0001
	assert math.abs(normal_radius - next_normal_radius) < 0.0001
	assert wrapped_distance(normal_angle, next_normal_angle) < 0.0001
}

fn test_rear_track_blend_slider_moves_endpoint_from_camera_to_course_end() {
	assert rear_track_blend_end(-4, -5, 1, 81, 0) == -4
	assert rear_track_blend_end(-4, -5, 1, 81, 50) == 36
	assert rear_track_blend_end(-4, -5, 1, 81, 100) == 76
	assert rear_track_blend_end(4, 5, -1, 81, 50) == -36
	assert rear_track_blend_factor(0, -4, -4) == 0
	assert rear_track_blend_factor(4, -4, 4) == 0
	assert rear_track_blend_factor(-4, -4, 4) == 1
	middle := rear_track_blend_factor(0, -4, 4)
	assert math.abs(middle - 0.75) < 0.0001
	assert rear_track_blend_factor(5, -4, 4) == 0
}

fn test_rear_track_blend_replaces_camera_side_wire_with_closed_panels() {
	mut simulation := new_visible_render_simulation()
	without_blend := simulation.render_course_snapshot_from_with_rear_blend(12, 16, 0, -4, 8, -4, 0)
	with_blend := simulation.render_course_snapshot_from_with_rear_blend(12, 16, 0, -4, 8, -4, 100)
	assert with_blend.len == without_blend.len
	mut faded_vertices := 0
	for index, vertex in with_blend {
		if vertex.brightness < without_blend[index].brightness - 0.0001 {
			faded_vertices++
		}
	}
	assert faded_vertices > 0
	assert with_blend[..32].all(it.brightness == 0)
}

fn test_surface_actor_placement_follows_backward_replay_course() {
	mut simulation := new_visible_render_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 18, turn_x: -0.04, turn_y: 0.02 }]
	}
	frame := simulation.actor_course_frame_at(-8)
	assert frame.distance == -8
	assert math.abs(frame.center_x) > 0.01
	assert math.abs(frame.center_y) > 0.01
}

fn test_invalid_render_soa_is_rejected_by_cpu_packer() {
	entities := RenderEntitySoa{
		angles: [f32(1)]
	}
	assert !entities.valid()
	assert pack_render_instances(entities).len == 0
}

// Test-side decoders for the packed data consumed by GLSL shaders.
struct EnemyRenderCode {
	tier    int
	seed    int
	damaged bool
}

fn decode_enemy_render_kind(value f32) EnemyRenderCode {
	tier := int_max(0, int_min(2, int((value - 3) / enemy_shape_tier_stride)))
	base := f32(3) + f32(tier) * enemy_shape_tier_stride
	packed := int((value - base) / enemy_shape_code_scale + 0.5)
	return EnemyRenderCode{
		tier: tier
		seed: packed % enemy_damaged_code_offset
		damaged: packed >= enemy_damaged_code_offset
	}
}

struct ParticleFragmentCode {
	spin_bin           int
	secondary_spin_bin int
	width_bin          int
	height_bin         int
}

fn decode_particle_fragment_payload(payload int) ParticleFragmentCode {
	return ParticleFragmentCode{
		spin_bin: payload & 63
		secondary_spin_bin: (payload >> 6) & 63
		width_bin: (payload >> 12) & 63
		height_bin: (payload >> 18) & 63
	}
}

fn multiplier_render_slot(kind f32) int {
	return int(math.round((kind - 20) / multiplier_list_slot_kind_scale))
}
