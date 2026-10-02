module sim

import math

fn close_shape_value(actual f32, expected f32) bool {
	return f32(math.abs(actual - expected)) < 0.000001
}

fn test_player_ship_geometry_matches_known_seed_one() {
	geometry := generate_ship_geometry(0, 1, false)
	assert close_shape_value(geometry.collision.x, 0.331177086)
	assert close_shape_value(geometry.collision.y, 1.38537145)
	assert geometry.color == 7
	assert geometry.rocket_offsets.len == 2
	assert close_shape_value(geometry.rocket_offsets[0], 0.0262288861)
	assert close_shape_value(geometry.rocket_offsets[1], -0.0262288861)
	assert geometry.structures.len == 4
	assert geometry.structures[0].shape == .rocket
	assert close_shape_value(geometry.structures[0].position.x, 0.524577737)
	assert close_shape_value(geometry.structures[0].width, 0.346342862)
	assert close_shape_value(geometry.structures[0].height, 2.30895233)
	assert geometry.structures[1].shape == .triangle
	assert close_shape_value(geometry.structures[1].position.x, 1.37889004)
	assert close_shape_value(geometry.structures[1].position.y, 0.651106894)
	assert close_shape_value(geometry.structures[1].rotation_z_degrees, 26.3437347)
	assert close_shape_value(geometry.structures[1].rotation_x_degrees, 5.44198608)
	assert close_shape_value(geometry.structures[1].width, 2.25012016)
	assert close_shape_value(geometry.structures[1].height, 3.73598766)
	assert geometry.structures[1].x_reverse == 1
	assert geometry.structures[1].color == 7
	assert geometry.structures[1].division_count == 5
	assert close_shape_value(geometry.structures[3].position.x, -1.37889004)
	assert close_shape_value(geometry.structures[3].rotation_z_degrees, -26.3437347)
	assert close_shape_value(geometry.structures[3].height, 3.57003117)
	assert geometry.structures[3].x_reverse == -1
}

fn test_seeded_enemy_geometry_matches_known_examples() {
	small := generate_ship_geometry(0, 25_308, false)
	assert small.structures.len == 3
	assert small.rocket_offsets == [f32(0)]
	assert close_shape_value(small.collision.x, 0.328683764)
	assert close_shape_value(small.collision.y, 0.724994957)
	assert small.structures[1].shape == .triangle

	middle := generate_ship_geometry(1, 79_042, false)
	assert middle.structures.len == 8
	assert middle.rocket_offsets.len == 4
	assert close_shape_value(middle.collision.x, 0.74762547)
	assert close_shape_value(middle.collision.y, 2.88094449)
	assert middle.structures[1].shape == .square
	assert close_shape_value(middle.structures[7].height, 9.21146488)

	large := generate_ship_geometry(2, 62_047, false)
	assert large.structures.len == 12
	assert large.rocket_offsets.len == 6
	assert close_shape_value(large.collision.x, 1.7378571)
	assert close_shape_value(large.collision.y, 5.57092762)
	assert close_shape_value(large.structures[11].position.x, -10.1120148)
}

fn test_odd_shaft_enemy_branches_match_known() {
	middle := generate_ship_geometry(1, 25_308, false)
	assert middle.structures.len == 7
	assert middle.rocket_offsets.len == 3
	assert close_shape_value(middle.collision.x, 0.823144734)
	assert close_shape_value(middle.collision.y, 1.66517329)
	assert middle.structures[1].shape == .square
	assert middle.structures[1].division_count == 8
	assert close_shape_value(middle.structures[6].position.x, -4.10095406)
	assert close_shape_value(middle.structures[6].height, 3.77244163)

	large := generate_ship_geometry(2, 25_308, false)
	assert large.structures.len == 11
	assert large.rocket_offsets.len == 5
	assert close_shape_value(large.collision.x, 1.80559504)
	assert close_shape_value(large.collision.y, 3.33034658)
	assert large.structures[1].shape == .square
	assert large.structures[1].division_count == 8
	assert close_shape_value(large.structures[10].position.x, -9.70565319)
	assert close_shape_value(large.structures[10].height, 8.79185963)
}

fn test_damaged_four_shaft_geometry_only_whitens_the_outer_pair() {
	normal := generate_ship_geometry(1, 79_042, false)
	damaged := generate_ship_geometry(1, 79_042, true)
	assert damaged.collision == normal.collision
	assert damaged.rocket_offsets == normal.rocket_offsets
	assert damaged.structures.len == normal.structures.len
	for index, structure in damaged.structures {
		assert structure.position == normal.structures[index].position
		assert structure.width == normal.structures[index].width
		assert structure.height == normal.structures[index].height
		if index < 4 {
			assert structure.color == normal.structures[index].color
		} else {
			assert structure.color == 0
		}
	}
}

fn test_collision_and_exhaust_helpers_share_complete_geometry() {
	for tier in 0 .. 3 {
		for seed in [1, 12_345, 62_047, 99_998] {
			geometry := generate_ship_geometry(tier, seed, false)
			assert ship_shape_collision(tier, seed) == geometry.collision
			assert ship_shape_rocket_offsets(tier, seed) == geometry.rocket_offsets
		}
	}
}
