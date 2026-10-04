module sim

import math

fn new_ship_mesh_test_simulation() Simulation {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.ship.lifecycle_counter = 0
	simulation.ship.invulnerable_ticks = 0
	return simulation
}

fn test_player_ship_mesh_uses_real_closed_panel_volume() {
	mut simulation := new_ship_mesh_test_simulation()
	vertices := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{})
	assert vertices.len > 100
	assert vertices.len % 3 == 0
	assert vertices.all(it.a < 0)
	mut minimum_y := f32(1000)
	mut maximum_y := f32(-1000)
	for vertex in vertices {
		minimum_y = f32_min(minimum_y, vertex.y)
		maximum_y = f32_max(maximum_y, vertex.y)
	}
	assert maximum_y - minimum_y > 0.01
}

fn test_tuning_ship_mesh_previews_keep_volume_at_requested_world_positions() {
	previews := [
		ShipMeshPreview{ kind: -1, x: -6, y: 4, z: 12, scale: 1 },
		ShipMeshPreview{ kind: 2, x: 7, y: -5, z: 12, scale: 1 },
	]
	vertices := render_ship_mesh_previews(previews)
	assert vertices.len > 200
	assert vertices.any(it.x < -5.5)
	assert vertices.any(it.x > 6.5)
	mut minimum_y := f32(1000)
	mut maximum_y := f32(-1000)
	mut minimum_z := f32(1000)
	mut maximum_z := f32(-1000)
	for vertex in vertices.filter(it.x < 0) {
		minimum_y = f32_min(minimum_y, vertex.y)
		maximum_y = f32_max(maximum_y, vertex.y)
		minimum_z = f32_min(minimum_z, vertex.z)
		maximum_z = f32_max(maximum_z, vertex.z)
	}
	assert maximum_y - minimum_y > 0.005
	assert maximum_z - minimum_z > 0.02
}

fn test_selected_tuning_ship_keeps_its_seeded_color() {
	vertices := render_ship_mesh_previews([ShipMeshPreview{
		kind: -1
		scale: 1
		selected: true
	}])
	assert vertices.any(f32(math.abs(it.b - it.r)) > 0.25)
}

fn test_seeded_enemy_mesh_differs_by_tier_and_keeps_surface_depth() {
	mut simulation := new_ship_mesh_test_simulation()
	simulation.zone_specs = ZoneEnemySpecs{
		small: [EnemySpec{ kind: 0, shape_seed: 25_308 }]
		boss: [EnemySpec{ kind: 2, shape_seed: 62_047 }]
	}
	simulation.enemies[0] = Enemy{
		alive: true
		kind: 0
		position: Vec2{ x: 0.3, y: 8 }
	}
	small := simulation.render_ship_mesh_vertices_for_camera(0.2, RenderScales{})
	simulation.enemies[0] = Enemy{
		alive: true
		kind: 2
		position: Vec2{ x: 0.3, y: 8 }
	}
	large := simulation.render_ship_mesh_vertices_for_camera(0.2, RenderScales{})
	assert large.len > small.len
	assert large.any(it.a > 0)
	assert large.any(math.abs(it.z - small[0].z) > 0.01)
}

fn test_ship_mesh_scale_changes_extent_without_changing_topology() {
	mut simulation := new_ship_mesh_test_simulation()
	normal := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{})
	double := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{ player: 2 })
	assert normal.len == double.len
	mut normal_extent := f32(0)
	mut double_extent := f32(0)
	normal_center := simulation.ship_mesh_frame(simulation.ship.angle, simulation.ship.relative_depth + ship_render_depth_offset, 0, -player_ship_surface_clearance(1), simulation.ship.bank).center
	double_center := simulation.ship_mesh_frame(simulation.ship.angle, simulation.ship.relative_depth + ship_render_depth_offset + player_ship_depth_clearance(2), 0, -player_ship_surface_clearance(2), simulation.ship.bank).center
	for index, vertex in normal {
		normal_point := ShipMeshVec3{ x: vertex.x, y: vertex.y, z: vertex.z }
		double_vertex := double[index]
		double_point := ShipMeshVec3{ x: double_vertex.x, y: double_vertex.y, z: double_vertex.z }
		normal_offset := normal_point.subtract(normal_center)
		double_offset := double_point.subtract(double_center)
		normal_extent = f32_max(normal_extent, f32(math.sqrt(f64(normal_offset.dot(normal_offset)))))
		double_extent = f32_max(double_extent, f32(math.sqrt(f64(double_offset.dot(double_offset)))))
	}
	assert double_extent > normal_extent * 1.9
}

fn test_scaled_ship_clearance_preserves_size_one_and_compensates_growth() {
	for kind in 0 .. 3 {
		baseline := enemy_surface_clearance(kind)
		normal := readable_hull_surface_clearance(kind, 1, baseline)
		double := readable_hull_surface_clearance(kind, 2, baseline)
		assert normal == baseline
		assert double > normal
		assert readable_hull_surface_clearance(kind, 0.5, baseline) == baseline
	}
}

fn test_scaled_player_hull_does_not_expand_toward_tunnel_wall() {
	mut simulation := new_ship_mesh_test_simulation()
	simulation.ship.bank = 0.48
	depth := simulation.ship.relative_depth + ship_render_depth_offset
	base_frame := simulation.ship_mesh_frame(simulation.ship.angle, depth, 0, 0, simulation.ship.bank)
	bank_sine := f32(math.sin(-simulation.ship.bank))
	bank_cosine := f32(math.cos(-simulation.ship.bank))
	outward := base_frame.lateral.multiply(bank_sine).add(base_frame.normal.multiply(bank_cosine))
	normal := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{})
	triple := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{ player: 3 })
	mut normal_outward := f32(-1000)
	mut triple_outward := f32(-1000)
	for vertex in normal {
		point := ShipMeshVec3{ x: vertex.x, y: vertex.y, z: vertex.z }
		normal_outward = f32_max(normal_outward, point.subtract(base_frame.center).dot(outward))
	}
	for vertex in triple {
		point := ShipMeshVec3{ x: vertex.x, y: vertex.y, z: vertex.z }
		triple_outward = f32_max(triple_outward, point.subtract(base_frame.center).dot(outward))
	}
	assert triple_outward <= normal_outward + 0.0001
}

fn test_ship_surface_frame_changes_with_circumference_without_tilting_longitudinal_axis() {
	mut simulation := new_ship_mesh_test_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.08, turn_y: -0.05 }]
	}
	left := simulation.ship_mesh_frame(0.2, 8, 0, 0, 0.35)
	right := simulation.ship_mesh_frame(1.7, 8, 0, 0, 0.35)
	assert left.forward.subtract(right.forward).dot(left.forward.subtract(right.forward)) < 0.000001
	assert left.normal.subtract(right.normal).dot(left.normal.subtract(right.normal)) > 0.1
	assert math.abs(left.lateral.dot(left.forward)) < 0.0001
	assert math.abs(left.normal.dot(left.forward)) < 0.0001
}

fn test_ship_mesh_frame_longitudinal_axis_follows_rendered_course_surface() {
	mut simulation := new_ship_mesh_test_simulation()
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.08, turn_y: -0.05 }]
	}
	depth := f32(8)
	angle := f32(0.7)
	camera_angle := f32(0.2)
	frame := simulation.ship_mesh_frame(angle, depth, camera_angle, 0, 0)
	mut previous_course := simulation.course_frame_at(depth - 0.5)
	mut next_course := simulation.course_frame_at(depth + 0.5)
	previous_course.radius /= source_tunnel_radius_ratio
	next_course.radius /= source_tunnel_radius_ratio
	previous_x, previous_y := course_surface_xy(previous_course, angle, camera_angle)
	next_x, next_y := course_surface_xy(next_course, angle, camera_angle)
	expected := ShipMeshVec3{
		x: next_x - previous_x
		y: next_y - previous_y
		z: course_render_depth_scale
	}.normalized()
	assert frame.forward.subtract(expected).dot(frame.forward.subtract(expected)) < 0.000001
	assert math.abs(frame.lateral.dot(frame.forward)) < 0.0001
	assert math.abs(frame.normal.dot(frame.forward)) < 0.0001
}

fn test_ship_bank_rolls_around_course_longitudinal_axis() {
	mut simulation := new_ship_mesh_test_simulation()
	unbanked := simulation.ship_mesh_frame(0.4, 4, 0.1, 0, 0)
	banked := simulation.ship_mesh_frame(0.4, 4, 0.1, 0, 0.5)
	assert unbanked.forward.subtract(banked.forward).dot(unbanked.forward.subtract(banked.forward)) < 0.000001
	assert unbanked.lateral.subtract(banked.lateral).dot(unbanked.lateral.subtract(banked.lateral)) > 0.01
}

fn test_ship_model_uses_source_longitudinal_and_radial_world_scales() {
	frame := ShipMeshFrame{
		lateral: ShipMeshVec3{ x: 1 }
		normal: ShipMeshVec3{ y: 1 }
		forward: ShipMeshVec3{ z: 1 }
	}
	radial := actor_ship_vertex(frame, ShipMeshVec3{ x: 1 }, 1)
	longitudinal := actor_ship_vertex(frame, ShipMeshVec3{ z: 1 }, 1)
	assert math.abs(radial.x - course_render_height_scale) < 0.000001
	assert math.abs(longitudinal.z - course_render_longitudinal_scale) < 0.000001
	assert longitudinal.z > radial.x
}

fn test_enemy_hulls_have_a_narrow_positive_z_nose_and_flat_negative_z_tail() {
	for kind in [0, 1, 2] {
		vertices := render_ship_mesh_previews([ShipMeshPreview{
			kind: kind
			scale: 1
		}])
		mut minimum_z := f32(1000)
		mut maximum_z := f32(-1000)
		for vertex in vertices {
			minimum_z = f32_min(minimum_z, vertex.z)
			maximum_z = f32_max(maximum_z, vertex.z)
		}
		mut nose_width := f32(0)
		mut tail_width := f32(0)
		for vertex in vertices {
			if vertex.z > maximum_z - 0.00001 {
				nose_width = f32_max(nose_width, f32(math.abs(vertex.x)))
			}
			if vertex.z < minimum_z + 0.00001 {
				tail_width = f32_max(tail_width, f32(math.abs(vertex.x)))
			}
		}
		assert maximum_z > 0
		assert minimum_z < 0
		assert nose_width < tail_width * 0.5
	}
}

fn test_enemy_hulls_have_low_long_racing_profiles() {
	for kind in [0, 1, 2] {
		vertices := render_ship_mesh_previews([ShipMeshPreview{
			kind: kind
			scale: 1
		}])
		mut minimum_y := f32(1000)
		mut maximum_y := f32(-1000)
		mut minimum_z := f32(1000)
		mut maximum_z := f32(-1000)
		for vertex in vertices {
			minimum_y = f32_min(minimum_y, vertex.y)
			maximum_y = f32_max(maximum_y, vertex.y)
			minimum_z = f32_min(minimum_z, vertex.z)
			maximum_z = f32_max(maximum_z, vertex.z)
		}
		minimum_length_ratio := if kind == 2 { f32(3.5) } else { f32(4) }
		assert maximum_z - minimum_z > (maximum_y - minimum_y) * minimum_length_ratio
	}
}

fn test_small_hull_is_rounded_and_boss_has_spiked_silhouette() {
	small := render_ship_mesh_previews([ShipMeshPreview{
		kind: 0
		scale: 1
	}])
	middle := render_ship_mesh_previews([ShipMeshPreview{
		kind: 1
		scale: 1
	}])
	boss := render_ship_mesh_previews([ShipMeshPreview{
		kind: 2
		scale: 1
	}])
	// The small interceptor uses two octagonal shells instead of rectangular
	// prisms, producing more radial facets than the medium craft.
	assert small.len > middle.len
	mut middle_x := f32(0)
	mut middle_z := f32(0)
	mut middle_y := f32(0)
	mut boss_x := f32(0)
	mut boss_z := f32(0)
	mut boss_y := f32(0)
	for vertex in middle {
		middle_x = f32_max(middle_x, f32(math.abs(vertex.x)))
		middle_y = f32_max(middle_y, vertex.y)
		middle_z = f32_max(middle_z, vertex.z)
	}
	for vertex in boss {
		boss_x = f32_max(boss_x, f32(math.abs(vertex.x)))
		boss_y = f32_max(boss_y, vertex.y)
		boss_z = f32_max(boss_z, vertex.z)
	}
	assert boss_x > middle_x * 1.7
	assert boss_y > middle_y * 2
	assert boss_z > middle_z * 1.5
}

fn test_player_uses_segmented_source_panels_while_enemies_use_solid_hulls() {
	player := render_ship_mesh_previews([ShipMeshPreview{
		kind: -1
		scale: 1
	}])
	small_enemy := render_ship_mesh_previews([ShipMeshPreview{
		kind: 0
		scale: 1
	}])
	assert player.all(it.a < -1)
	assert player.any(math.abs(f64(-it.a - 1 - 0.5)) < 0.001)
	assert small_enemy.all(math.abs(f64(it.a - 0.94)) < 0.001)
	assert player.len != small_enemy.len
}

fn test_ship_palette_remains_visibly_colored() {
	for index in 2 .. 8 {
		color := ship_structure_color(index)
		maximum := f32_max(color.r, f32_max(color.g, color.b))
		minimum := f32_min(color.r, f32_min(color.g, color.b))
		assert maximum - minimum >= 0.5
	}
	player := ship_structure_color(generate_ship_geometry(0, 1, false).color)
	assert player.b > player.g
	assert player.g > player.r
}

fn test_every_new_hull_applies_its_configured_scale_proportionally() {
	for kind in [-1, 0, 1, 2] {
		normal := render_ship_mesh_previews([ShipMeshPreview{
			kind: kind
			scale: 1
		}])
		double := render_ship_mesh_previews([ShipMeshPreview{
			kind: kind
			scale: 2
		}])
		assert normal.len == double.len
		mut normal_extent := f32(0)
		mut double_extent := f32(0)
		for index, vertex in normal {
			normal_extent = f32_max(normal_extent, f32(math.sqrt(f64(vertex.x * vertex.x + vertex.y * vertex.y + vertex.z * vertex.z))))
			double_vertex := double[index]
			double_extent = f32_max(double_extent, f32(math.sqrt(f64(double_vertex.x * double_vertex.x + double_vertex.y * double_vertex.y + double_vertex.z * double_vertex.z))))
		}
		assert math.abs(double_extent / normal_extent - 2) < 0.0001
	}
}

fn test_boss_nose_faces_the_course_forward_direction() {
	mut simulation := new_ship_mesh_test_simulation()
	simulation.ship.lifecycle_counter = -229
	simulation.zone_specs = ZoneEnemySpecs{
		boss: [EnemySpec{ kind: 2, shape_seed: 62_047 }]
	}
	enemy := Enemy{
		alive: true
		kind: 2
		position: Vec2{ x: 0.4, y: 8 }
		turn_speed: 0.25
	}
	simulation.enemies[0] = enemy
	vertices := simulation.render_ship_mesh_vertices_for_camera(0, RenderScales{})
	clearance := readable_hull_surface_clearance(2, 1, enemy_surface_clearance(2))
	base_frame := simulation.ship_mesh_frame(enemy.position.x, enemy.position.y, 0, -clearance, enemy.turn_speed)
	mut tail_depth := f32(1000)
	mut nose_depth := f32(-1000)
	for vertex in vertices {
		point := ShipMeshVec3{ x: vertex.x, y: vertex.y, z: vertex.z }
		depth := point.subtract(base_frame.center).dot(base_frame.forward)
		tail_depth = f32_min(tail_depth, depth)
		nose_depth = f32_max(nose_depth, depth)
	}
	assert tail_depth < 0
	assert nose_depth > 0
	mut nose_width := f32(0)
	mut tail_width := f32(0)
	for vertex in vertices {
		point := ShipMeshVec3{ x: vertex.x, y: vertex.y, z: vertex.z }
		offset := point.subtract(base_frame.center)
		depth := offset.dot(base_frame.forward)
		width := f32(math.abs(f64(offset.dot(base_frame.lateral))))
		if depth > nose_depth - 0.00001 {
			nose_width = f32_max(nose_width, width)
		}
		if depth < tail_depth + 0.00001 {
			tail_width = f32_max(tail_width, width)
		}
	}
	assert nose_width < tail_width * 0.5
}

fn test_scaled_player_hull_center_does_not_bob_while_banking() {
	mut simulation := new_ship_mesh_test_simulation()
	clearance := player_ship_surface_clearance(5)
	neutral := simulation.ship_mesh_frame(0.7, -2.5, 0.2, -clearance, 0)
	for bank in [f32(-1.2), -0.5, 0.5, 1.2] {
		banked := simulation.ship_mesh_frame(0.7, -2.5, 0.2, -clearance, bank)
		delta := banked.center.subtract(neutral.center)
		assert delta.dot(delta) < 0.000001
		assert banked.forward.subtract(neutral.forward).dot(banked.forward.subtract(neutral.forward)) < 0.000001
	}
}

fn test_scaled_player_tail_is_moved_away_from_camera_plane() {
	assert player_ship_depth_clearance(1) == 0
	assert player_ship_depth_clearance(10) > 2.4
	assert player_ship_depth_clearance(10) < 2.5
}
