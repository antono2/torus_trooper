// Regression coverage for seeded gameplay, entity lifetimes, collisions and difficulty rules.
module sim

import math

fn living_destruction_particles(simulation &Simulation) int {
	mut count := 0
	for particle in simulation.particles {
		if particle.alive && particle.kind in [.spark, .fragment] {
			count++
		}
	}
	return count
}

fn test_mt19937_matches_expected_reference_sequence() {
	mut rng := new_mt19937(5489)
	expected := [u32(3499211612), 581869302, 3890346734, 3586334585, 545404204, 4161255391,
		3922919429, 949333985, 2715962298, 1323567403]
	for value in expected {
		assert rng.next_u32() == value
	}
}

fn test_mt19937_helpers_match_expected_ranges() {
	mut first := new_mt19937(42)
	mut second := new_mt19937(42)
	assert first.next_int(0) == 0
	assert first.next_int(17) == int(second.next_u32() % 17)
	value := first.next_signed_f32(3)
	assert value >= -3
	assert value <= 3
}

fn test_disappearing_bullet_reserves_its_pool_slot_for_45_ticks() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.spawn(Vec2{}, 0, 0, -1)
	simulation.bullets[0].start_disappearing()
	assert simulation.bullets[0].alive
	assert simulation.bullets[0].disappear_ticks == 1
	assert !simulation.spawn(Vec2{}, 0, 0, -1)
	simulation.update_bullets()
	assert simulation.bullets[0].age == 1
	assert simulation.bullets[0].disappear_ticks == 2
	for _ in 0 .. 44 {
		simulation.update_bullets()
	}
	assert simulation.bullets[0].disappear_ticks == 0
	assert simulation.spawn(Vec2{}, 0, 0, -1)
}

fn test_hostile_bullet_starts_disappearing_after_six_hundred_moves() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.spawn(Vec2{ y: 1 }, 0, 0, -1)
	for _ in 0 .. 600 {
		simulation.update_bullets()
	}
	assert simulation.bullets[0].age == 600
	assert simulation.bullets[0].disappear_ticks == 0
	simulation.update_bullets()
	assert simulation.bullets[0].age == 601
	assert simulation.bullets[0].disappear_ticks == 1
	simulation.update_bullets()
	assert simulation.bullets[0].disappear_ticks == 2
}

fn test_subsystem_random_streams_start_equal_and_advance_independently() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	expected := simulation.random.next_u32()
	assert simulation.stage_random.next_u32() == expected
	assert simulation.barrage_random.next_u32() == expected
	assert simulation.enemy_random.next_u32() == expected
	assert simulation.shot_random.next_u32() == expected
	assert simulation.particle_random.next_u32() == expected
	assert simulation.ship_random.next_u32() == expected

	stage_before := simulation.stage_random.next_u32()
	for _ in 0 .. 20 {
		simulation.random.next_u32()
	}
	mut reference := new_mt19937(u32(simulation.config.random_seed))
	_ = reference.next_u32()
	assert stage_before == reference.next_u32()
	assert simulation.stage_random.next_u32() == reference.next_u32()
}

fn test_bullet_randomness_does_not_perturb_stage_spawns() {
	config := SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	}
	mut first := new_simulation(config)
	mut second := new_simulation(config)
	for _ in 0 .. 100 {
		first.random.next_u32()
	}
	first.ship.speed = 1
	second.ship.speed = 1
	first.next_small_distance = 0.5
	second.next_small_distance = 0.5
	first.next_middle_distance = 999
	second.next_middle_distance = 999
	first.update_stage_spawning()
	second.update_stage_spawning()
	assert first.enemies[0].position == second.enemies[0].position
	assert first.enemies[0].spec_index == second.enemies[0].spec_index
}

fn test_grade_rules_match_configured_constants() {
	normal := rules_for_grade(.normal)
	hard := rules_for_grade(.hard)
	extreme := rules_for_grade(.extreme)
	assert normal.name == 'NORMAL'
	assert normal.letter == 'N'
	assert normal.default_speed == 0.4
	assert normal.max_speed == 0.8
	assert normal.accel_ratio == 0.002
	assert normal.bank_max == 0.8
	assert normal.boss_app_rank == 100
	assert hard.default_speed == 0.6
	assert hard.max_speed == 1.2
	assert hard.accel_ratio == 0.003
	assert hard.bank_max == 1.0
	assert hard.boss_app_rank == 160
	assert extreme.default_speed == 0.8
	assert extreme.max_speed == 1.6
	assert extreme.accel_ratio == 0.004
	assert extreme.bank_max == 1.2
	assert extreme.boss_app_rank == 250
}

fn test_grade_changes_ship_acceleration_and_bank_limits() {
	mut normal := new_simulation(SimulationConfig{ grade: .normal, barrage: Barrage{ emitters: [] } })
	mut extreme := new_simulation(SimulationConfig{ grade: .extreme, barrage: Barrage{ emitters: [] } })
	for _ in 0 .. 120 {
		normal.update_with_input(InputState{ left: true, up: true })
		extreme.update_with_input(InputState{ left: true, up: true })
	}
	assert extreme.ship.target_speed > normal.ship.target_speed
	assert extreme.ship.speed > normal.ship.speed
	assert extreme.ship.bank > normal.ship.bank
}

fn test_eye_smoothing_sight_depth_and_screen_shake_are_deterministic() {
	mut first := new_simulation(SimulationConfig{ grade: .normal, barrage: Barrage{ emitters: [] } })
	mut second := new_simulation(SimulationConfig{ grade: .normal, barrage: Barrage{ emitters: [] } })
	first.ship.angle = 1
	second.ship.angle = 1
	first.ship.relative_depth = relative_depth_max
	second.ship.relative_depth = relative_depth_max
	first.ship.speed = 1
	second.ship.speed = 1
	first.ship.screen_shake_ticks = 32
	second.ship.screen_shake_ticks = 32
	first.ship.screen_shake_intensity = 0.05
	second.ship.screen_shake_intensity = 0.05
	first.update_ship(InputState{})
	second.update_ship(InputState{})
	first.sample_screen_shake()
	second.sample_screen_shake()
	assert first.ship.eye_angle > 0
	assert first.ship.eye_angle < first.ship.angle
	assert first.ship.sight_depth > 70
	assert first.ship.camera_shake_angle == second.ship.camera_shake_angle
	assert first.ship.camera_shake_x == second.ship.camera_shake_x
	assert first.ship.camera_shake_y == second.ship.camera_shake_y
	assert first.ship.camera_shake_x != 0
	assert first.ship.camera_shake_y != 0
	assert first.ship.screen_shake_ticks == 31
}

fn test_ship_stars_consume_rng_before_screen_shake_sampling() {
	mut shaken := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	mut still := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	shaken.ship.screen_shake_ticks = 32
	shaken.ship.screen_shake_intensity = 0.05
	shaken.update()
	still.update()
	shaken_stars := shaken.particles.filter(it.alive && it.kind == .star)
	still_stars := still.particles.filter(it.alive && it.kind == .star)
	assert shaken_stars == still_stars
	assert f32(math.abs(shaken.ship.camera_shake_angle)) + f32(math.abs(shaken.ship.camera_shake_x)) + f32(math.abs(shaken.ship.camera_shake_y)) > 0
}

fn test_live_boss_bits_are_exposed_as_derived_render_poses() {
	spec := EnemySpec{
		kind: 2
		bit_count: 4
		bit_formation: .round
		bit_distance: 0.5
		bit_angular_step: 0.02
	}
	mut simulation := new_simulation(SimulationConfig{})
	simulation.zone_specs = ZoneEnemySpecs{ boss: [spec] }
	simulation.enemies[0] = Enemy{
		alive: true
		kind: 2
		spec_index: 0
		age: 15
		position: Vec2{ x: 1.2, y: 20 }
	}
	poses := simulation.boss_bits()
	assert poses.len == 4
	assert poses[0].position.x != simulation.enemies[0].position.x
	assert poses[0].position.y != simulation.enemies[0].position.y
}

fn test_stage_rank_gate_matches_expected_boss_progression() {
	mut stage := new_stage_progression(.normal, 2)
	assert stage.boss_appearance_rank == 98
	assert stage.zone_end_rank == 100
	for _ in 0 .. 97 {
		assert !stage.rank_up(false)
	}
	assert !stage.in_boss_mode
	assert !stage.rank_up(false)
	assert stage.in_boss_mode
	assert stage.rank == 98

	// Ordinary enemies cannot affect rank during a boss encounter.
	assert !stage.rank_up(false)
	stage.rank_down()
	assert stage.rank == 98
	assert !stage.rank_up(true)
	assert stage.bosses_remaining == 1
	assert stage.rank_up(true)
	assert stage.rank == 100
	assert stage.zone_complete_pending

	stage.start_next_zone(1)
	assert stage.zone == 2
	assert stage.boss_appearance_rank == 199
	assert stage.zone_end_rank == 200
	assert !stage.zone_complete_pending
}

fn test_forced_stage_completion_preserves_rank() {
	mut stage := new_stage_progression(.hard, 1)
	for _ in 0 .. 12 {
		stage.rank_up(false)
	}
	stage.force_zone_complete()
	assert stage.rank == 12
	assert stage.zone_complete_pending
	stage.start_next_zone(3)
	assert stage.boss_appearance_rank == 317
	assert stage.zone_end_rank == 320
}

fn test_live_stage_uses_distance_spawns_and_delayed_zone_transition() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.speed = 1
	simulation.next_small_distance = 0.5
	simulation.next_middle_distance = 999
	simulation.update_stage_spawning()
	assert simulation.spawned_enemies == 1
	assert simulation.enemies.last().kind == 0

	simulation.stage.rank = simulation.stage.boss_appearance_rank - 1
	simulation.record_enemy_rank_up(false)
	assert simulation.stage.in_boss_mode
	simulation.next_boss_distance = 0
	simulation.update_stage_spawning()
	assert simulation.count_living_bosses() == 1

	assert simulation.spawn(Vec2{}, 0, 0, -1)
	simulation.record_enemy_rank_up(true)
	assert simulation.zone == 1
	assert simulation.zone_transition_ticks == 60
	assert simulation.living_bullets() == 1
	for _ in 0 .. 61 {
		simulation.update_stage_spawning()
	}
	assert simulation.living_bullets() == 0
	assert simulation.living_enemies() == 0
	assert simulation.zone == 2
	assert simulation.zone_advances == 1
	assert simulation.stage.zone == 2
	assert !simulation.stage.zone_complete_pending
	assert simulation.palette_transition_ticks == 59
	assert simulation.next_small_distance >= 5
	assert simulation.next_small_distance <= 20
}

fn test_zone_spec_count_loop_re_evaluates_the_source_random_bound() {
	mut rng := new_mt19937(77)
	specs := generate_zone_enemy_specs(1, .normal, true, 1, mut rng)
	assert specs.small.len == 2
	assert specs.middle.len == 3
	assert specs.boss.len == 1
	assert specs.small.map(it.shape_seed) == [57_495, 25_222]
	assert specs.middle.map(it.shape_seed) == [27_158, 72_757, 84_592]
	assert specs.boss.map(it.shape_seed) == [19_482]
	assert rng.next_u32() == 1_903_929_109
}

fn test_morph_selection_keeps_the_source_fixed_table_and_backward_fallback() {
	mut rng := new_mt19937(77)
	morphs := select_morph_patterns(8, mut rng)
	assert morphs == ['morph/fire_slowshot', 'morph/divide', 'morph/fast', 'morph/bar', 'morph/twin',
		'morph/wedge_half', 'morph/accelshot', 'morph/accel']
	assert rng.next_u32() == 375_034_592
}

fn test_generated_enemy_specs_are_seeded_and_match_expected_ranges() {
	mut first_rng := new_mt19937(77)
	mut second_rng := new_mt19937(77)
	first := generate_zone_enemy_specs(8, .hard, false, 3, mut first_rng)
	second := generate_zone_enemy_specs(8, .hard, false, 3, mut second_rng)
	assert first == second
	assert first.small.len >= 2 && first.small.len <= 3
	assert first.middle.len >= 2 && first.middle.len <= 3
	assert first.boss.len == 3
	for spec in first.small {
		assert spec.shield == 1
		assert spec.score == 100
		assert spec.shape_seed >= 0 && spec.shape_seed < 99_999
		assert spec.base_speed >= 0.05 && spec.base_speed < 0.15
		assert spec.ship_speed_ratio >= 0.25 && spec.ship_speed_ratio < 0.5
		assert spec.barrage.base_pattern == 'basic/straight'
		assert spec.barrage.visual_scale == 1
		assert !spec.barrage.long_range
		assert !spec.barrage.no_x_reverse
		assert !spec.aim_ship
		assert !spec.has_limit_depth
		assert !spec.no_fire_depth_limit
	}
	for spec in first.middle {
		assert spec.shield == 10
		assert spec.score == 500
		assert spec.shape_seed >= 0 && spec.shape_seed < 99_999
		assert spec.barrage.base_pattern.starts_with('middle/')
		assert spec.barrage.visual_scale == 1
		assert !spec.barrage.long_range
		assert !spec.barrage.no_x_reverse
		assert !spec.aim_ship
		assert !spec.has_limit_depth
		assert !spec.no_fire_depth_limit
	}
	for spec in first.boss {
		assert spec.shield == 30
		assert spec.score == 2000
		assert spec.shape_seed >= 0 && spec.shape_seed < 99_999
		assert spec.bit_count == 2 || spec.bit_count == 4 || spec.bit_count == 6
		assert spec.bit_formation != .none
		assert spec.bit_barrage.base_pattern == 'basic/straight'
		assert spec.barrage.visual_scale == 1.2
		assert spec.bit_barrage.visual_scale == 1
		assert spec.barrage.long_range
		assert !spec.barrage.no_x_reverse
		assert spec.bit_barrage.long_range
		assert spec.bit_barrage.no_x_reverse
		assert spec.aim_ship
		assert spec.has_limit_depth
		assert spec.no_fire_depth_limit
	}
}

fn test_middle_boss_specs_have_no_bits() {
	mut rng := new_mt19937(91)
	specs := generate_zone_enemy_specs(7, .normal, true, 2, mut rng)
	assert specs.boss.all(it.middle_boss)
	assert specs.boss.all(it.bit_count == 0)
	assert specs.boss.all(it.bit_formation == .none)
	assert specs.boss.all(it.aim_ship && it.has_limit_depth && it.no_fire_depth_limit)
}

fn test_stage_construction_draws_initial_spawn_distances_in_source_order() {
	seed := u32(77)
	mut expected_random := new_mt19937(seed)
	expected := generate_zone_enemy_setup(1, .normal, true, 0, mut expected_random)
	simulation := new_simulation(SimulationConfig{
		stage_progression: true
		random_seed: seed
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.next_small_distance == expected.next_small_distance
	assert simulation.next_middle_distance == expected.next_middle_distance
	assert simulation.zone_specs == expected.specs
}

fn test_high_starting_level_applies_seeded_multi_boss_generation_immediately() {
	simulation := new_simulation(SimulationConfig{
		stage_progression: true
		starting_level: 20
		random_seed: 1
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.zone_specs.boss.len == 3
	assert simulation.zone_specs.boss.map(it.shape_seed) == [66_126, 27_211, 12_809]
	assert simulation.stage.bosses_remaining == 3
	assert simulation.stage.boss_appearance_rank == 97
}

fn test_stage_enemies_spawn_at_expected_depth_inside_the_course() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		procedural_course: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 1, right: 2, rad: 21 }]
	}
	assert simulation.spawn_stage_enemy(0)
	small := simulation.enemies.filter(it.alive)[0]
	assert small.position.y >= 140 && small.position.y < 157.5
	assert small.position.x >= 1 && small.position.x <= 2
	assert small.limit_depth == small.position.y
	assert simulation.spawn_stage_enemy(2)
	boss := simulation.enemies.filter(it.alive && it.kind == 2)[0]
	assert boss.position.y == 140
	assert boss.position.x >= 1 && boss.position.x <= 2
	assert boss.limit_depth == 140
}

fn test_stage_spawn_carries_a_non_positive_distance_deficit() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.speed = 0
	simulation.next_small_distance = -2
	simulation.next_middle_distance = 999
	simulation.update_stage_spawning()
	assert simulation.spawned_enemies == 1
	assert simulation.next_small_distance >= 4
	assert simulation.next_small_distance <= 19
}

fn test_stage_enemy_pool_allocates_backwards_and_resets_with_the_zone() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		enemy_capacity: 3
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.spawn_stage_enemy(0)
	assert simulation.enemies[2].alive
	assert simulation.spawn_stage_enemy(0)
	assert simulation.enemies[1].alive
	simulation.clear_live_enemies()
	assert simulation.enemy_cursor == 0
	assert simulation.spawn_stage_enemy(0)
	assert simulation.enemies[2].alive
}

fn test_full_stage_enemy_pool_still_consumes_source_spawn_argument_draws() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		enemy_capacity: 0
		barrage: Barrage{ emitters: [] }
	})
	mut expected := simulation.stage_random
	_ = expected.next_int(simulation.zone_specs.small.len)
	_ = expected.next_f32(17.5)
	assert !simulation.spawn_stage_enemy(0)
	assert simulation.stage_random.next_u32() == expected.next_u32()
}

fn test_generated_boss_aims_and_keeps_its_longitudinal_limit() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.angle = 0
	simulation.ship.speed = 0.3
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 3, y: 140 }
		health: 30
		kind: 2
		limit_depth: 140
	}
	simulation.update_enemies()
	assert simulation.enemies[0].turn_speed < 0
	assert simulation.enemies[0].position.x < 3
	assert simulation.enemies[0].position.y < 140
	assert simulation.enemies[0].limit_depth < 140
}

fn test_only_generated_bosses_ignore_the_firing_depth_limit() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.angle = 0
	simulation.ship.eye_angle = 0
	far_enemy := Enemy{ alive: true, position: Vec2{ x: 0, y: 100 } }
	assert !simulation.generated_enemy_can_fire(far_enemy, EnemySpec{})
	assert simulation.generated_enemy_can_fire(far_enemy, EnemySpec{
		no_fire_depth_limit: true
	})
	near_enemy := Enemy{ alive: true, position: Vec2{ x: 0, y: 19 } }
	assert !simulation.generated_enemy_can_fire(near_enemy, EnemySpec{
		no_fire_depth_limit: true
	})
}

fn test_seeded_ship_collision_rectangles_match_expected_tiers() {
	player := ship_shape_collision(0, 1)
	assert player == ship_shape_collision(0, 1)
	assert player.x > 0.2 && player.x < 0.5
	assert player.y > 0.6 && player.y < 1.5
	middle := ship_shape_collision(1, 42)
	large := ship_shape_collision(2, 42)
	assert middle.x > player.x
	assert middle.y > player.y
	assert large.x > middle.x
	assert large.y > middle.y
}

fn test_seeded_ship_shape_rocket_offsets_match_each_shaft_tier() {
	small := ship_shape_rocket_offsets(0, 1)
	assert small.len in [1, 2]
	if small.len == 1 {
		assert small[0] == 0
	} else {
		assert small[0] == -small[1]
		assert small[0] > 0.018 && small[0] < 0.027
	}
	middle := ship_shape_rocket_offsets(1, 42)
	assert middle.len in [3, 4]
	assert middle.all(f32(math.abs(it)) < 0.14)
	large := ship_shape_rocket_offsets(2, 42)
	assert large.len in [5, 6]
	assert large.all(f32(math.abs(it)) < 0.42)
}

fn test_fragment_rng_continues_after_final_seeded_boss_shape() {
	mut source := new_mt19937(9)
	specs := generate_zone_enemy_specs(8, .normal, false, 2, mut source)
	mut first := shape_random_after_zone(specs, 1)
	mut second := shape_random_after_zone(specs, 99)
	assert first.next_u32() == second.next_u32()
}

fn test_enemy_ship_contact_starts_expected_forty_eight_tick_flip() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.speed = 1
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 0.1 }
		health: 1
	}
	simulation.update_enemies()
	assert simulation.enemies[0].flip_ticks == 48
	assert simulation.enemies[0].flip_velocity.y > 6.9
	assert simulation.ship.hits == 0
	before := simulation.enemies[0].position.y
	simulation.update_enemies()
	assert simulation.enemies[0].flip_ticks == 47
	assert simulation.enemies[0].position.y > before + 6
}

fn test_boss_bit_formations_match_expected_offsets() {
	line := EnemySpec{
		bit_count: 4
		bit_formation: .line
		bit_distance: 0.5
	}
	left := boss_bit_pose(line, Vec2{ x: 2, y: 10 }, 0, 0)
	right := boss_bit_pose(line, Vec2{ x: 2, y: 10 }, 1, 0)
	assert left.position.x == 1.25
	assert right.position.x == 2.75
	assert left.position.y == 10
	assert left.direction == f32(math.pi)

	round := EnemySpec{
		bit_count: 4
		bit_formation: .round
		bit_distance: 0.5
		bit_angular_step: 0.02
	}
	top := boss_bit_pose(round, Vec2{ x: 2, y: 10 }, 0, 0)
	assert top.position.x == 2
	assert top.position.y == 15
	rotated := boss_bit_pose(round, Vec2{ x: 2, y: 10 }, 0, 9)
	assert math.abs(rotated.rotation - f32(math.pi) * 63 / 180) < 0.0001
}

fn test_live_boss_fires_from_body_and_each_bit() {
	barrage := GeneratedBarrageSpec{
		base_pattern: 'basic/straight'
		rank: 0.2
		speed_rank: 1
	}
	spec := EnemySpec{
		kind: 2
		shield: 30
		score: 2000
		barrage: barrage
		bit_count: 2
		bit_formation: .line
		bit_distance: 0.5
		bit_barrage: barrage
	}
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	simulation.zone_specs = ZoneEnemySpecs{ boss: [spec] }
	simulation.fire_enemy_pattern(EnemyFire{
		position: Vec2{ x: 2, y: 10 }
		kind: 2
		spec_index: 0
	})
	assert simulation.enemy_shots_fired == 3
	assert simulation.living_bullets() == 3
}

fn test_enemy_owned_pattern_root_uses_its_generated_post_wait() {
	spec := EnemySpec{
		barrage: GeneratedBarrageSpec{
			base_pattern: 'basic/straight'
			rank: 0.2
			speed_rank: 1
			interval: 2
		}
	}
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut enemy := Enemy{ alive: true, position: Vec2{ x: 1, y: 30 } }
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	assert simulation.enemy_shots_fired == 1
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	assert simulation.enemy_shots_fired == 1
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	assert simulation.enemy_shots_fired == 2
}

fn test_stage_enemy_updates_owned_root_instead_of_generic_age_modulus() {
	spec := EnemySpec{
		kind: 0
		shield: 1
		base_speed: 0.1
		ship_speed_ratio: 0.5
		barrage: GeneratedBarrageSpec{
			base_pattern: 'basic/straight'
			rank: 0.2
			speed_rank: 1
			interval: 2
		}
	}
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		enemy_fire_interval: 75
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	simulation.zone_specs = ZoneEnemySpecs{ small: [spec] }
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 30 }
		health: 1
	}
	simulation.update()
	assert simulation.enemies[0].age == 1
	assert simulation.enemy_shots_fired == 1
}

fn test_enemy_owned_pattern_root_advances_while_body_fire_is_suppressed() {
	spec := EnemySpec{
		barrage: GeneratedBarrageSpec{
			base_pattern: 'basic/straight'
			rank: 0.2
			speed_rank: 1
			interval: 2
		}
	}
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut enemy := Enemy{ alive: true, position: Vec2{ x: 1, y: 30 } }
	simulation.update_generated_enemy_patterns(mut enemy, spec, false)
	assert simulation.enemy_shots_fired == 0
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	assert simulation.enemy_shots_fired == 0
	simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	assert simulation.enemy_shots_fired == 1
}

fn test_enemy_owned_middle_root_rewinds_without_a_generic_fire_interval() {
	spec := EnemySpec{
		barrage: GeneratedBarrageSpec{
			base_pattern: 'basic/straight'
			rank: 0.2
			speed_rank: 1
		}
	}
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut enemy := Enemy{ alive: true, position: Vec2{ x: 1, y: 30 } }
	for _ in 0 .. 3 {
		simulation.update_generated_enemy_patterns(mut enemy, spec, true)
	}
	assert simulation.enemy_shots_fired == 3
}

fn test_boss_bit_roots_preserve_expected_long_range_gate_behavior() {
	straight := GeneratedBarrageSpec{
		base_pattern: 'basic/straight'
		rank: 0.2
		speed_rank: 1
		no_x_reverse: true
		long_range: true
	}
	spec := EnemySpec{
		kind: 2
		barrage: straight
		bit_count: 2
		bit_formation: .line
		bit_distance: 0.5
		bit_barrage: straight
	}
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut enemy := Enemy{ alive: true, kind: 2, position: Vec2{ x: 1, y: 140 } }
	simulation.update_generated_enemy_patterns(mut enemy, spec, false)
	assert simulation.enemy_shots_fired == 2
	assert simulation.bullets[0].long_range
	assert simulation.bullets[0].x_reverse == 1
}

fn test_plain_bullets_advance_through_native_morph_pipeline() {
	base := straight_pattern()
	morph := PatternProgram{
		name: 'test/morph'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(10)
				direction_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	simulation.emit_pattern_pipeline(Vec2{ x: 1, y: 10 }, 1, PatternPipeline{
		programs: [base, morph]
		ranks: [f32(0), 0.75]
	}, 0.5)
	assert simulation.living_bullets() == 1
	assert simulation.bullet_patterns[0].active
	assert simulation.bullet_patterns[0].morph_seed
	assert simulation.bullet_patterns[0].pipeline_index == 1
	assert simulation.bullet_patterns[0].runner.context.rank == 0.75

	simulation.update()
	assert simulation.living_bullets() == 1
	assert simulation.bullets[0].alive
	assert !simulation.bullet_patterns[0].active
	assert f32(math.abs(simulation.bullets[0].direction - (1 + 10 * math.pi / 180))) < 0.000001
}

fn test_inline_child_action_stays_in_current_pipeline_stage() {
	base := twin_pattern()
	morph := straight_pattern()
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut top := new_pattern_runner(base, PatternContext{ base_speed: 0.5 })
	assert top.tick(mut simulation.random)!.len == 0
	assert top.tick(mut simulation.random)!.len == 0
	shot := top.tick(mut simulation.random)![0]
	assert simulation.spawn_pipeline_shot(Vec2{ y: 10 }, PatternPipeline{
		programs: [base, morph]
		ranks: [f32(0.2), 0.6]
	}, 0, base, 0.2, shot)
	assert simulation.bullet_patterns[0].pipeline_index == 0
	assert !simulation.bullet_patterns[0].morph_seed
}

fn test_extension_threshold_scales_with_expected_level_formula() {
	assert extend_score_for_level(1) == 100000
	assert extend_score_for_level(2) == 110000
	assert extend_score_for_level(20) == 200000
	assert extend_score_for_level(98) == 500000
	assert extend_score_for_level(200) == 500000
	mut simulation := new_simulation(SimulationConfig{
		starting_level: 20
		barrage: Barrage{ emitters: [] }
	})
	assert simulation.level == 20
	assert simulation.next_extend_score == 200000
}

fn test_braking_stores_and_releases_regenerative_speed() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	simulation.update_with_input(InputState{ brake: true })
	assert simulation.ship.speed == 0.975
	assert simulation.ship.regenerative_charge == 0.025
	simulation.update()
	assert simulation.ship.speed > 0.977
	assert simulation.ship.regenerative_charge == 0.0225
}

fn test_whole_tunnel_units_add_expected_distance_score() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.ship.distance = 0.25
	simulation.ship.speed = 0.9
	simulation.ship.target_speed = 0.9
	simulation.update()
	assert f32(math.abs(simulation.ship.distance - 1.15)) < 0.000001
	assert simulation.score == 1
	simulation.ship.speed = 2.2
	simulation.ship.target_speed = 2.2
	simulation.update()
	assert simulation.score == 3
}

fn test_straight_barrage_spawns_on_schedule() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{
			emitters: [Emitter{
				interval: 10
				bullet_speed: 0.25
			}]
		}
	})
	mut control := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	mut expected_leading_depth := f32(0)
	for _ in 0 .. 21 {
		simulation.update()
		control.update()
		expected_leading_depth += 0.25 * control.ship.speed * 5
	}
	assert simulation.living_bullets() == 3
	assert simulation.bullets[0].age == 21
	assert simulation.bullets[1].age == 11
	assert simulation.bullets[2].age == 1
	assert simulation.bullets[0].position.x == 0
	assert f32(math.abs(simulation.bullets[0].position.y - expected_leading_depth)) < 0.000001
}

fn test_simulation_is_deterministic() {
	mut first := new_simulation(SimulationConfig{})
	mut second := new_simulation(SimulationConfig{})
	for _ in 0 .. 600 {
		first.update()
		second.update()
	}
	assert first.checksum() == second.checksum()
	assert first.living_bullets() == second.living_bullets()
}

fn test_default_actor_pool_capacities_match_the() {
	simulation := new_simulation(SimulationConfig{})
	assert simulation.bullets.len == 512
	assert simulation.shots.len == 64
	assert simulation.enemies.len == 64
	assert simulation.particles.len == 1024
	assert simulation.multiplier_popups.len == 16
}

fn test_seeded_background_stars_spawn_per_unit_of_ship_travel() {
	mut first := new_simulation(SimulationConfig{})
	mut second := new_simulation(SimulationConfig{})
	first.tick = 1
	second.tick = 1
	first.ship.speed = 0.4
	second.ship.speed = 0.4
	first.ship.angle = 0.2
	second.ship.angle = 0.2
	first.ship.lifecycle_counter = -229
	second.ship.lifecycle_counter = -229
	first.spawn_ship_particles()
	second.spawn_ship_particles()
	assert first.living_particles() == 5
	assert first.particles == second.particles
	assert first.next_star_distance == 1
	for particle in first.particles {
		if particle.alive {
			assert particle.kind == .star
			assert particle.position.y == 32
			assert particle.life >= 100 && particle.life < 150
			assert particle.height >= -64 && particle.height <= -8
			assert !particle.in_course
		}
	}
	first.spawn_ship_particles()
	first.spawn_ship_particles()
	assert first.living_particles() == 5
	first.spawn_ship_particles()
	assert first.living_particles() == 10
}

fn test_background_stars_cover_both_screen_halves() {
	mut simulation := new_simulation(SimulationConfig{
		particle_capacity: 128
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.angle = 0.4
	for _ in 0 .. 20 {
		simulation.spawn_background_stars()
	}
	stars := simulation.particles.filter(it.alive && it.kind == .star)
	assert stars.len == 100
	assert stars.any(f32(math.cos(f64(it.position.x - simulation.ship.angle))) > 0)
	assert stars.any(f32(math.cos(f64(it.position.x - simulation.ship.angle))) < 0)
}

fn test_fixed_player_shape_emits_two_seeded_rocket_jets_each_tick() {
	mut first := new_simulation(SimulationConfig{})
	mut second := new_simulation(SimulationConfig{})
	first.next_star_distance = 100
	second.next_star_distance = 100
	first.ship.lifecycle_counter = -228
	second.ship.lifecycle_counter = -228
	first.ship.angle = 1
	second.ship.angle = 1
	first.spawn_ship_particles()
	second.spawn_ship_particles()
	assert first.living_particles() == 2
	assert first.particles == second.particles
	jets := first.particles.filter(it.alive)
	assert jets.all(it.kind == .jet)
	assert jets.any(it.position.x > 1.0262 && it.position.x < 1.0263)
	assert jets.any(it.position.x > 0.9737 && it.position.x < 0.9738)
	for jet in jets {
		assert jet.life >= 16 && jet.life < 24
		assert jet.velocity.y >= -0.24
		assert jet.velocity.y <= -0.08
		assert jet.height == 1
		assert jet.in_course
	}
}

fn test_player_rocket_jets_follow_the_bank_offset() {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.next_star_distance = 100
	simulation.ship.lifecycle_counter = -228
	simulation.ship.angle = 1
	simulation.ship.bank = 0.5
	simulation.spawn_ship_particles()
	jets := simulation.particles.filter(it.alive)
	assert jets.len == 2
	assert jets.any(it.position.x > 0.9762 && it.position.x < 0.9763)
	assert jets.any(it.position.x > 0.9237 && it.position.x < 0.9238)
}

fn test_visible_enemy_emits_seeded_shape_rocket_jets() {
	spec := EnemySpec{
		kind: 1
		shape_seed: 42
	}
	mut simulation := new_simulation(SimulationConfig{
		enemy_capacity: 1
		particle_capacity: 16
		barrage: Barrage{ emitters: [] }
	})
	simulation.zone_specs = ZoneEnemySpecs{ middle: [spec] }
	simulation.ship.sight_depth = 35
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: 10 }
		kind: 1
		spec_index: 0
	}
	simulation.update_enemies()
	offsets := ship_shape_rocket_offsets(1, 42)
	assert simulation.living_particles() == offsets.len
	for particle in simulation.particles {
		if particle.alive {
			assert particle.kind == .jet
			assert particle.visual_tier == 1
			assert particle.position.y == simulation.enemies[0].position.y - 0.15
			assert particle.life >= 16 && particle.life < 24
		}
	}
}

fn test_enemy_outside_sight_does_not_emit_rocket_jets() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.sight_depth = 35
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: 40 }
	}
	simulation.update_enemies()
	assert simulation.living_particles() == 0
}

fn test_particles_move_with_the_ship_and_leave_behind_the_tunnel() {
	mut simulation := new_simulation(SimulationConfig{ particle_capacity: 1 })
	simulation.ship.speed = 0.6
	simulation.particles[0] = Particle{
		alive: true
		position: Vec2{ x: 0.5, y: -1.5 }
		life: 100
		initial_life: 100
		kind: .star
	}
	simulation.update_particles()
	assert simulation.particles[0].alive
	assert simulation.particles[0].position.y < -2
	simulation.update_particles()
	assert !simulation.particles[0].alive
}

fn test_long_seeded_run_remains_deterministic_and_within_capacity() {
	config := SimulationConfig{
		bullet_capacity: 256
		shot_capacity: 32
		enemy_capacity: 48
		particle_capacity: 128
		enemy_interval: 37
		enemy_fire_interval: 29
		collisions: true
		random_seed: 0x1234_5678_9abc_def0
		barrage: Barrage{
			emitters: [Emitter{
				interval: 11
				bullets_per_volley: 5
				spread: 1.2
				bullet_speed: 0.08
			}]
		}
	}
	mut first := new_simulation(config)
	mut second := new_simulation(config)
	for tick in 0 .. 12_000 {
		input := InputState{
			left: tick % 240 < 60
			right: tick % 240 >= 120 && tick % 240 < 180
			up: tick % 300 < 150
			fire: tick % 5 != 0
			brake: tick % 600 >= 500
		}
		first.update_with_input(input)
		second.update_with_input(input)
	}
	assert first.checksum() == second.checksum()
	assert first.bullets.len == config.bullet_capacity
	assert first.shots.len == config.shot_capacity
	assert first.enemies.len == config.enemy_capacity
	assert first.particles.len == config.particle_capacity
}

fn test_capacity_drops_spawns_without_corrupting_live_bullets() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 2
		barrage: Barrage{ emitters: [Emitter{ interval: 1 }] }
	})
	for _ in 0 .. 3 {
		simulation.update()
	}
	assert simulation.living_bullets() == 2
	assert simulation.bullets[0].age == 3
	assert simulation.bullets[1].age == 2
}

fn test_native_motion_program_changes_speed_over_time() {
	program := MotionProgram{
		name: 'accelerate_then_vanish'
		steps: [
			MotionStep{ at_age: 0, kind: .change_speed, target: 0.5, duration: 4 },
			MotionStep{ at_age: 6, kind: .vanish },
		]
	}
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [Emitter{ first_shot_tick: 1000 }] }
		programs: [program]
	})
	assert simulation.spawn(Vec2{}, 0, 0.1, 0)
	for _ in 0 .. 4 {
		simulation.update()
	}
	assert simulation.bullets[0].speed == 0.5
	assert simulation.bullets[0].alive
	for _ in 0 .. 3 {
		simulation.update()
	}
	assert !simulation.bullets[0].alive
}

fn test_live_bullet_pool_executes_child_pattern_actions() {
	program := twin_pattern()
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut parent := new_pattern_runner(program, PatternContext{
		rank: 0.5
		base_direction: 1
		base_speed: 0.5
	})
	assert parent.tick(mut simulation.random)!.len == 0
	assert parent.tick(mut simulation.random)!.len == 0
	spawned := parent.tick(mut simulation.random) or { panic(err) }
	assert spawned.len == 2
	assert simulation.spawn_pattern_shot(Vec2{ x: 1, y: 10 }, program, 0.5, spawned[0])
	assert simulation.living_bullets() == 1
	for _ in 0 .. 5 {
		simulation.update()
	}
	assert simulation.living_bullets() == 1
	assert simulation.bullets[0].age == 0
	assert f32(math.abs(simulation.bullets[0].direction - 1)) < 0.000001
	assert simulation.bullets[0].speed == 0.5
	assert simulation.bullet_patterns.all(!it.active)
}

fn test_completed_child_action_keeps_bullet_and_finishes_speed_transition() {
	program := accelshot_pattern()
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 8
		barrage: Barrage{ emitters: [] }
	})
	mut parent := new_pattern_runner(program, PatternContext{
		base_direction: f32(math.pi / 2)
		base_speed: 1
	})
	spawned := parent.tick(mut simulation.random) or { panic(err) }
	assert spawned.len == 1
	assert spawned[0].speed > 0.099
	assert spawned[0].speed < 0.101
	assert simulation.spawn_pipeline_shot(Vec2{ x: 1, y: 140 }, PatternPipeline{
		programs: [program]
		ranks: [f32(0)]
		long_range: true
	}, 0, program, 0, spawned[0])
	for _ in 0 .. 70 {
		simulation.update()
	}
	assert simulation.living_bullets() == 1
	assert simulation.bullets[0].speed == 1
	assert simulation.bullet_patterns.all(!it.active)
}

fn test_direction_change_takes_shortest_path() {
	program := MotionProgram{
		name: 'turn_across_wrap'
		steps: [MotionStep{
			at_age: 0
			kind: .change_direction
			target: -3.0
			duration: 2
		}]
	}
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [Emitter{ first_shot_tick: 1000 }] }
		programs: [program]
	})
	assert simulation.spawn(Vec2{}, 3.0, 0, 0)
	simulation.update()
	assert simulation.bullets[0].direction > 3.0
	simulation.update()
	assert simulation.bullets[0].direction > 3.2
}

fn test_spread_volley_is_symmetric() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{
			name: 'three_way'
			emitters: [Emitter{
				interval: 60
				bullets_per_volley: 3
				spread: 1.0
			}]
		}
	})
	simulation.update()
	assert simulation.living_bullets() == 3
	assert simulation.bullets[0].direction == -0.5
	assert simulation.bullets[1].direction == 0
	assert simulation.bullets[2].direction == 0.5
}

fn test_ship_input_is_applied_on_simulation_ticks() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 10 {
		simulation.update_with_input(InputState{ left: true, up: true })
	}
	assert simulation.ship.angle > 0
	assert simulation.ship.bank > 0
	assert simulation.ship.relative_depth > 0.499
	assert simulation.ship.relative_depth < 0.501
	assert simulation.ship.target_speed > 0
	assert simulation.ship.speed > 0
	assert simulation.tick == 10
}

fn test_ship_longitudinal_input_uses_a_camera_shifted_five_unit_range() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 100 {
		simulation.update_ship(InputState{ up: true })
	}
	assert simulation.ship.relative_depth == relative_depth_max
	simulation.ship.relative_depth = relative_depth_max - 0.04
	simulation.update_ship(InputState{ up: true })
	assert simulation.ship.relative_depth == relative_depth_max
	simulation.ship.relative_depth = relative_depth_min + 0.04
	simulation.update_ship(InputState{ down: true })
	assert simulation.ship.relative_depth == relative_depth_min
}

fn test_ship_and_bullet_angles_wrap_for_collision() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.angle = 0.01
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	simulation.ship.lifecycle_counter = 1
	simulation.ship.invulnerable_ticks = 0
	assert simulation.spawn(Vec2{ x: 6.28, y: 0.25 }, f32(math.pi), 0.1, -1)
	simulation.update()
	assert simulation.ship.hits == 1
	assert simulation.ship.invulnerable_ticks == 268
	assert !simulation.bullets[0].alive
}

fn test_stationary_hostile_bullet_does_not_trigger_swept_collision() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.lifecycle_counter = 1
	simulation.ship.invulnerable_ticks = 0
	assert simulation.spawn(Vec2{ x: 0, y: 0 }, 0, 0, -1)
	simulation.update()
	assert simulation.ship.hits == 0
	assert simulation.bullets[0].alive
}

fn test_primary_fire_uses_expected_two_tick_interval() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 5 {
		simulation.update_with_input(InputState{ fire: true })
	}
	assert simulation.fired_shots == 3
	assert simulation.living_shots() == 3
	assert simulation.shots[63].age == 5
	assert simulation.shots[62].age == 3
	assert simulation.shots[61].age == 1
	assert simulation.shots[63].position.x > 6.2
	assert simulation.shots[62].position.x == 0.05
	assert simulation.shots[63].star_shell
}

fn test_configurable_player_shot_distance_scales_regular_side_and_charged_ranges() {
	mut simulation := new_simulation(SimulationConfig{
		player_shot_distance: 70
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.speed = 0.8
	simulation.ship.target_speed = 0.8
	simulation.side_fire_cooldown = 0
	simulation.update_weapon(InputState{ fire: true })
	regular_ranges := simulation.shots.filter(it.alive).map(it.range)
	assert regular_ranges.len == 2
	assert regular_ranges.all(it == 70)

	mut charged := new_simulation(SimulationConfig{
		player_shot_distance: 70
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 23 {
		charged.update_weapon(InputState{ brake: true })
		charged.update_shots()
	}
	index := charged.charging_shot
	charged.update_weapon(InputState{})
	assert math.abs(charged.shots[index].range - 27) < 0.0001
}

fn test_charge_forcibly_replaces_the_next_shot_pool_slot() {
	mut simulation := new_simulation(SimulationConfig{
		shot_capacity: 2
		barrage: Barrage{ emitters: [] }
	})
	simulation.shots[0] = Shot{ alive: true, age: 40, range: 35 }
	simulation.shots[1] = Shot{ alive: true, age: 20, range: 35 }
	simulation.update_with_input(InputState{ brake: true })
	assert simulation.charging_shot == 1
	assert simulation.shots[0].alive
	assert simulation.shots[0].age == 41
	assert simulation.shots[1].alive
	assert simulation.shots[1].charged
	assert simulation.shots[1].charging
	assert simulation.shots[1].charge_ticks == 1
}

fn test_charging_shot_follows_the_bank_offset_rocket_position() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.ship.angle = 1
	simulation.ship.bank = 0.5
	simulation.update_weapon(InputState{ brake: true })
	index := simulation.charging_shot
	assert index == 63
	assert simulation.shots[index].position.x > 0.949 && simulation.shots[index].position.x < 0.951
}

fn test_gameplay_start_latch_requires_action_release_without_suppressing_direction() {
	mut simulation := new_simulation(SimulationConfig{
		release_before_action: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.update_with_input(InputState{ left: true, fire: true })
	assert simulation.ship.bank > 0
	assert simulation.fired_shots == 0
	simulation.update_with_input(InputState{ fire: true })
	assert simulation.fired_shots == 0
	simulation.update_with_input(InputState{})
	assert !simulation.action_latched
	simulation.update_with_input(InputState{ fire: true })
	assert simulation.fired_shots == 1
}

fn test_high_speed_primary_fire_adds_side_shots() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.ship.speed = 0.8
	simulation.ship.target_speed = 0.8
	simulation.side_fire_cooldown = 0
	simulation.update_with_input(InputState{ fire: true })
	assert simulation.fired_shots == 1
	assert simulation.side_fired_shots == 1
	assert simulation.living_shots() == 2
	for _ in 0 .. 8 {
		simulation.update_with_input(InputState{ fire: true })
	}
	assert simulation.side_fired_shots > 1
	assert simulation.shots.any(it.alive && f32(math.abs(f64(it.direction))) > 0.001)
}

fn test_star_shell_does_not_clear_enemy_bullet() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 0.3 }
		range: 35
		star_shell: true
	}
	assert simulation.spawn(Vec2{ x: 0.05, y: 1.05 }, 0, 0, -1)
	simulation.update()
	assert simulation.bullets_cleared == 0
	assert simulation.living_bullets() == 1
}

fn test_two_charged_shots_cannot_clear_the_same_disappearing_bullet_twice() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	for index in 0 .. 2 {
		simulation.shots[index] = Shot{
			alive: true
			position: Vec2{ x: 0, y: 0.3 }
			range: 35
			charged: true
		}
	}
	assert simulation.spawn(Vec2{ x: 0.05, y: 1.05 }, 0, 0, -1)
	simulation.update_shots()
	assert simulation.bullets_cleared == 1
	assert simulation.bullets[0].disappear_ticks == 1
	assert simulation.score == 10
	assert simulation.shots[0].multiplier == 2
	assert simulation.shots[1].multiplier == 1
}

fn test_charged_shot_scores_hostile_bullet_with_current_multiplier() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.shots[0] = Shot{
		alive: true
		charged: true
		multiplier: 2
		position: Vec2{ x: 0, y: 0.3 }
		range: 35
	}
	assert simulation.spawn(Vec2{ x: 0.05, y: 1.05 }, 0, 0, -1)
	simulation.update_shots()
	assert simulation.bullets_cleared == 1
	assert simulation.score == 20
	assert simulation.shots[0].multiplier == 3
	assert simulation.living_multiplier_popups() == 1
	popup := simulation.multiplier_popups[simulation.multiplier_popup_cursor]
	assert popup.multiplier == 2
	assert !popup.large_label
}

fn test_star_shell_emits_one_seeded_trail_particle_after_moving() {
	mut first := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	mut second := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	shot := Shot{
		alive: true
		star_shell: true
		position: Vec2{ x: 0.2, y: 1 }
		range: 35
	}
	first.shots[0] = shot
	second.shots[0] = shot
	first.update_shots()
	second.update_shots()
	assert first.living_particles() == 1
	assert first.particles == second.particles
	particle := first.particles.filter(it.alive)[0]
	assert particle.position == first.shots[0].position
	assert particle.position.y == 1.75
	assert particle.life >= 4 && particle.life < 6
	assert particle.kind == .spark
	assert particle.height == 1
}

fn test_charged_shot_emits_three_trails_from_twenty_three_ticks() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.shots[0] = Shot{
		alive: true
		charged: true
		charging: true
		charge_ticks: 22
	}
	simulation.update_shots()
	assert simulation.shots[0].charge_ticks == 23
	assert simulation.living_particles() == 3
	for particle in simulation.particles {
		if particle.alive {
			assert particle.life >= 12 && particle.life < 18
		}
	}
}

fn test_zero_range_frame_still_hits_before_shot_removal() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 0.3 }
		range: 0.5
	}
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 1.05 }
		health: 1
		score: 100
	}
	simulation.update_shots()
	assert !simulation.shots[0].alive
	assert !simulation.enemies[0].alive
	assert simulation.destroyed_enemies == 1
	assert simulation.score == 100
}

fn test_short_charge_is_discarded_on_release() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 22 {
		simulation.update_with_input(InputState{ brake: true })
	}
	assert simulation.living_shots() == 1
	simulation.update()
	assert simulation.living_shots() == 0
	assert simulation.charging_shot == -1
}

fn test_charged_shot_releases_and_pierces_enemies() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 23 {
		simulation.update_with_input(InputState{ brake: true })
	}
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 1.05 }
		health: 3
	}
	simulation.update()
	assert !simulation.enemies[0].alive
	assert simulation.living_shots() == 1
	shot := simulation.shots.filter(it.alive)[0]
	assert shot.charged
	assert !shot.charging
	assert shot.damage == 100
	assert shot.multiplier == 2
	assert simulation.living_multiplier_popups() == 0
}

fn test_charged_shot_kill_shows_the_floating_multiplier() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0.4, y: 4 }
		health: 1
		score: 500
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0.4, y: 3.285 }
		range: 35
		charged: true
		damage: 100
		multiplier: 2
	}
	simulation.update()
	assert simulation.score == 1000
	assert simulation.shots[0].multiplier == 3
	assert simulation.living_multiplier_popups() == 1
	popup := simulation.multiplier_popups[15]
	assert popup.multiplier == 2
	assert popup.large_label
	assert popup.life == 29
	assert popup.alpha > 0.76 && popup.alpha < 0.78
	assert popup.position.y > 4 && popup.position.y <= 4.2
}

fn test_multiplier_popup_pool_and_rng_are_fixed_and_deterministic() {
	mut first := new_simulation(SimulationConfig{})
	mut second := new_simulation(SimulationConfig{})
	for multiplier in 2 .. 19 {
		position := Vec2{ x: f32(multiplier) * 0.01, y: 3 }
		first.spawn_multiplier_popup(position, multiplier, 100)
		second.spawn_multiplier_popup(position, multiplier, 100)
	}
	assert first.living_multiplier_popups() == 16
	assert second.living_multiplier_popups() == 16
	assert first.multiplier_popups == second.multiplier_popups
	first.update_multiplier_popups()
	assert first.living_multiplier_popups() == 16
	for _ in 0 .. 36 {
		first.update_multiplier_popups()
	}
	assert first.living_multiplier_popups() == 0
}

fn test_charge_can_be_held_past_maximum_and_still_release() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 300 {
		simulation.update_with_input(InputState{ brake: true })
	}
	assert simulation.living_shots() == 1
	index := simulation.charging_shot
	assert index == 63
	assert simulation.shots[index].charging
	assert simulation.shots[index].charge_ticks == 90
	assert simulation.shots[index].size > 4.48 && simulation.shots[index].size < 4.49
	simulation.update()
	assert simulation.living_shots() == 1
	assert !simulation.shots[index].charging
	assert simulation.shots[index].range > 40
	assert simulation.shots[index].target_size > 13.59 && simulation.shots[index].target_size < 13.61
	assert simulation.shots[index].size > 5.39 && simulation.shots[index].size < 5.41
}

fn test_charged_shot_size_expands_the_enemy_collision_rectangle() {
	config := SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	}
	mut charged := new_simulation(config)
	mut regular := new_simulation(config)
	enemy := Enemy{
		alive: true
		position: Vec2{ x: 0.25, y: 4 }
		health: 1
	}
	charged.enemies[0] = enemy
	regular.enemies[0] = enemy
	charged.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 3.25 }
		range: 35
		charged: true
		damage: 100
		size: 4
		target_size: 4
	}
	regular.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 3.25 }
		range: 35
		size: 1
		target_size: 1
	}
	charged.update_shots()
	regular.update_shots()
	assert !charged.enemies[0].alive
	assert regular.enemies[0].alive
}

fn test_enemy_spawning_is_seeded_and_deterministic() {
	config := SimulationConfig{
		enemy_interval: 10
		barrage: Barrage{ emitters: [] }
	}
	mut first := new_simulation(config)
	mut second := new_simulation(config)
	for _ in 0 .. 21 {
		first.update()
		second.update()
	}
	assert first.living_enemies() == 3
	assert first.enemies[0].position.x == second.enemies[0].position.x
	assert first.enemies[1].position.x == second.enemies[1].position.x
	assert first.checksum() == second.checksum()
}

fn test_every_fifth_spawn_is_a_middle_enemy() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_interval: 1
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 5 {
		simulation.update()
	}
	assert simulation.spawned_enemies == 5
	assert simulation.enemies[0].kind == 0
	assert simulation.enemies[0].pattern == 0
	assert simulation.enemies[1].pattern == 1
	assert simulation.enemies[2].pattern == 2
	assert simulation.enemies[0].health == 1
	assert simulation.enemies[4].kind == 1
	assert simulation.enemies[4].health == 10
	assert simulation.enemies[4].score == 500
}

fn test_middle_enemy_fires_three_way_volley() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_fire_interval: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: 20 }
		health: 10
		kind: 1
		score: 500
	}
	simulation.update()
	assert simulation.enemy_shots_fired == 3
	assert simulation.living_bullets() == 3
	assert simulation.bullets[0].direction != simulation.bullets[1].direction
	assert simulation.bullets[1].direction != simulation.bullets[2].direction
}

fn test_twentieth_spawn_is_a_large_enemy() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_interval: 1
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 20 {
		simulation.update()
	}
	assert simulation.spawned_enemies == 20
	assert simulation.enemies[19].kind == 2
	assert simulation.enemies[19].health == 30
	assert simulation.enemies[19].score == 2000
}

fn test_large_enemy_fires_five_way_volley() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_fire_interval: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: 20 }
		health: 30
		kind: 2
		score: 2000
	}
	simulation.update()
	assert simulation.enemy_shots_fired == 5
	assert simulation.living_bullets() == 5
	assert simulation.bullets[0].direction != simulation.bullets[4].direction
}

fn test_middle_enemy_weaves_deterministically() {
	mut first := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	mut second := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	enemy := Enemy{
		alive: true
		position: Vec2{ x: 1, y: 20 }
		health: 10
		kind: 1
		pattern: 1
	}
	first.enemies[0] = enemy
	second.enemies[0] = enemy
	for _ in 0 .. 30 {
		first.update()
		second.update()
	}
	assert first.enemies[0].position.x != 1
	assert first.enemies[0].position.x == second.enemies[0].position.x
}

fn test_boss_steers_across_shortest_tunnel_seam() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.ship.angle = 0.01
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 6.20, y: 20 }
		health: 30
		kind: 2
	}
	before := wrapped_distance(simulation.enemies[0].position.x, simulation.ship.angle)
	for _ in 0 .. 30 {
		simulation.update()
	}
	after := wrapped_distance(simulation.enemies[0].position.x, simulation.ship.angle)
	assert after < before
}

fn test_timed_run_counts_down_and_ends() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 33
		barrage: Barrage{ emitters: [] }
	})
	simulation.update()
	assert simulation.remaining_time_ms == 16
	assert !simulation.game_over
	simulation.update()
	assert simulation.remaining_time_ms == 0
	assert simulation.game_over
	previous_tick := simulation.tick
	simulation.update_with_input(InputState{ fire: true })
	assert simulation.tick == previous_tick + 1
	assert simulation.fired_shots == 0
}

fn test_god_mode_holds_zero_time_without_game_over() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 16
		barrage: Barrage{ emitters: [] }
	})
	simulation.god_mode = true
	simulation.update()
	assert simulation.remaining_time_ms == 0
	assert !simulation.game_over
	simulation.update()
	assert simulation.remaining_time_ms == 0
	assert !simulation.game_over
	simulation.god_mode = false
	simulation.update()
	assert simulation.game_over
}

fn test_source_clock_uses_seventeen_millisecond_steps() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 7058 {
		simulation.update()
	}
	assert simulation.remaining_time_ms == 14
	assert !simulation.game_over
	simulation.update()
	assert simulation.remaining_time_ms == 0
	assert simulation.game_over
}

fn test_zero_time_precedes_game_over_as_in_the_source() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 34
		barrage: Barrage{ emitters: [] }
	})
	simulation.update()
	simulation.update()
	assert simulation.remaining_time_ms == 0
	assert !simulation.game_over
	simulation.update()
	assert simulation.game_over
}

fn test_game_over_keeps_world_motion_and_fades_hostile_bullets() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 33
		bullet_capacity: 2
		enemy_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.game_over = true
	simulation.remaining_time_ms = 0
	simulation.ship.lifecycle_counter = 1
	simulation.ship.speed = 1
	simulation.ship.target_speed = 0
	simulation.ship.distance = 0.5
	simulation.bullets[0] = Bullet{
		alive: true
		position: Vec2{ x: 0, y: 5 }
		direction: 0
		speed: 0.1
	}
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 10 }
		health: 1
	}
	simulation.update_with_input(InputState{ fire: true, up: true })
	assert f32(math.abs(simulation.ship.speed - 0.855)) < 0.000001
	assert f32(math.abs(simulation.ship.distance - 1.355)) < 0.000001
	assert simulation.bullets[0].position.y > 5
	assert simulation.bullets[0].disappear_ticks == 2
	assert simulation.enemies[0].age == 1
	assert simulation.fired_shots == 0
	assert simulation.score == 0
	assert simulation.remaining_time_ms == 0
}

fn test_pre_restart_window_recenters_depth_until_source_invincibility_boundary() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.lifecycle_counter = -230
	simulation.ship.relative_depth = 5
	simulation.bullets[0] = Bullet{ alive: true, position: Vec2{ x: 0, y: 5 } }
	simulation.update_with_input(InputState{ fire: true, up: true })
	assert simulation.ship.lifecycle_counter == -229
	assert f32(math.abs(simulation.ship.relative_depth - 4.95)) < 0.000001
	assert simulation.bullets[0].disappear_ticks == 2
	assert simulation.fired_shots == 0
	simulation.update()
	assert simulation.ship.lifecycle_counter == -228
	assert f32(math.abs(simulation.ship.relative_depth - 4.95)) < 0.000001
}

fn test_respawn_immediately_removes_existing_and_new_enemy_bullets() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 4
		barrage: Barrage{
			emitters: [Emitter{
				position: Vec2{ x: 0, y: 8 }
				interval: 1
				bullet_speed: 0.1
			}]
		}
	})
	simulation.ship.lifecycle_counter = -229
	simulation.bullets[0] = Bullet{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		disappear_ticks: 12
	}
	simulation.bullet_patterns[0].active = true
	simulation.update()
	assert simulation.ship.lifecycle_counter == -228
	assert simulation.living_bullets() == 0
	assert simulation.bullets.all(!it.alive && it.disappear_ticks == 0)
	assert simulation.bullet_patterns.all(!it.active)
}

fn test_game_over_holds_a_destroyed_ship_at_the_restart_delay() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.game_over = true
	simulation.ship.lifecycle_counter = -268
	simulation.update()
	assert simulation.ship.lifecycle_counter == -268
	assert simulation.ship.invulnerable_ticks == 268
}

fn test_game_over_enemy_destruction_does_not_change_score_or_rank() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		stage_progression: true
		enemy_capacity: 1
		shot_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.game_over = true
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 3.25 }
		health: 1
		score: 100
	}
	simulation.shots[0] = Shot{
		alive: true
		charged: true
		position: Vec2{ x: 0, y: 3.25 }
		range: 35
		size: 1
		target_size: 1
		multiplier: 2
	}
	simulation.update_shots()
	assert !simulation.enemies[0].alive
	assert simulation.score == 0
	assert simulation.stage.rank == 0
	assert simulation.living_multiplier_popups() == 1
}

fn test_ship_hit_applies_fifteen_second_penalty() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.lifecycle_counter = 1
	simulation.ship.invulnerable_ticks = 0
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	assert simulation.spawn(Vec2{ x: 0, y: 0.5 }, f32(math.pi), 0.2, -1)
	simulation.update()
	assert simulation.ship.hits == 1
	assert simulation.remaining_time_ms == 104_983
	assert simulation.time_change_seconds == -15
	assert simulation.time_change_ticks == 239
	assert simulation.living_particles() >= 256
	assert simulation.particles.filter(it.alive).all(it.life == it.initial_life - 1)
	assert f32(math.abs(simulation.ship.camera_shake_angle)) + f32(math.abs(simulation.ship.camera_shake_x)) + f32(math.abs(simulation.ship.camera_shake_y)) > 0
}

fn test_god_mode_ignores_ship_hits_without_consuming_the_hostile_bullet() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.god_mode = true
	simulation.ship.lifecycle_counter = 1
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	assert simulation.spawn(Vec2{ x: 0, y: 0.5 }, f32(math.pi), 0.2, -1)
	simulation.update()
	assert simulation.ship.hits == 0
	assert simulation.ship.lifecycle_counter > 0
	assert simulation.remaining_time_ms == 119_983
	assert simulation.bullets[0].alive
}

fn test_ship_restart_has_expected_hidden_and_invincible_windows() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.lifecycle_counter = 1
	simulation.ship.invulnerable_ticks = 0
	simulation.ship.target_speed = 1
	simulation.ship.regenerative_charge = 0.5
	simulation.destroy_ship()
	assert simulation.ship.lifecycle_counter == -268
	assert simulation.ship.target_speed == 0
	assert simulation.ship.regenerative_charge == 0
	assert simulation.living_particles() == 256

	for _ in 0 .. 39 {
		simulation.update_with_input(InputState{ fire: true, up: true })
	}
	assert simulation.ship.lifecycle_counter == -229
	assert simulation.fired_shots == 0
	simulation.update_with_input(InputState{ fire: true, up: true })
	assert simulation.ship.lifecycle_counter == -228
	assert simulation.fired_shots == 1
	for _ in 0 .. 228 {
		simulation.update()
	}
	assert simulation.ship.lifecycle_counter == 0
	assert simulation.ship.invulnerable_ticks == 0
	simulation.update()
	assert simulation.ship.lifecycle_counter == 1
}

fn test_course_position_wraps_and_increments_lap() {
	mut simulation := new_simulation(SimulationConfig{
		course_length: 10
		barrage: Barrage{ emitters: [] }
	})
	simulation.ship.course_position = 9.5
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	simulation.update()
	assert simulation.ship.lap == 2
	assert simulation.ship.course_position > 0.49
	assert simulation.ship.course_position < 0.51
}

fn test_presentation_course_position_smoothly_extrapolates_and_wraps() {
	mut simulation := new_simulation(SimulationConfig{ course_length: 10 })
	simulation.ship.course_position = 9.9
	simulation.ship.speed = 0.4
	simulation.ship.presentation_course_step = 0.4
	assert math.abs(simulation.presentation_course_position(0.0) - 9.9) < 0.00001
	assert math.abs(simulation.presentation_course_position(0.25) - 0.0) < 0.00001
	assert math.abs(simulation.presentation_course_position(0.5) - 0.1) < 0.00001
	assert math.abs(simulation.presentation_course_position(2.0) - 0.3) < 0.00001
}

fn test_presentation_course_motion_uses_travel_before_later_speed_correction() {
	mut simulation := new_simulation(SimulationConfig{ course_length: 10 })
	simulation.ship.course_position = 0.2
	simulation.ship.presentation_course_step = 0.4
	// Border collision and other end-of-tick corrections may change the speed
	// after the course already moved. Presentation must follow actual travel.
	simulation.ship.speed = 0.05
	assert math.abs(simulation.presentation_course_position(0.5) - 0.4) < 0.00001
	assert math.abs(wrapped_course_delta(9.8, 0.2, 10) - 0.4) < 0.00001
}

fn test_presentation_ship_pose_extrapolates_fixed_tick_camera_motion() {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.ship.relative_depth = 2
	simulation.ship.eye_angle = f32(math.pi * 2) - 0.01
	simulation.ship.presentation_depth_step = 0.1
	simulation.ship.presentation_eye_step = 0.02
	simulation.ship.angle = f32(math.pi * 2) - 0.02
	simulation.ship.presentation_angle_step = 0.04
	simulation.ship.bank = 0.2
	simulation.ship.presentation_bank_step = -0.1
	assert math.abs(simulation.presentation_relative_depth(0.5) - 2.05) < 0.00001
	assert math.abs(simulation.presentation_eye_angle(0.5)) < 0.00001
	assert math.abs(simulation.presentation_ship_angle(0.5)) < 0.00001
	assert math.abs(simulation.presentation_ship_bank(0.5) - 0.15) < 0.00001
	simulation.ship.relative_depth = relative_depth_max
	assert simulation.presentation_relative_depth(1) == relative_depth_max
}

fn test_enemy_reovertake_decreases_rank_outside_boss_mode() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.stage.rank = 10
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ y: 0 }
		kind: 0
		rank_counted: true
		speed: 1
	}
	simulation.update_enemies()
	assert simulation.enemies[0].position.y > simulation.ship.relative_depth
	assert simulation.enemies[0].rank_counted
	assert simulation.stage.rank == 10
	simulation.update_enemies()
	assert !simulation.enemies[0].rank_counted
	assert simulation.stage.rank == 9
}

fn test_exhausted_boss_encounter_forces_transition_without_time_bonus() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		run_time_ms: 120_000
		barrage: Barrage{ emitters: [] }
	})
	simulation.remaining_time_ms = 50_000
	simulation.stage.in_boss_mode = true
	simulation.next_boss_spec = simulation.zone_specs.boss.len
	simulation.next_boss_distance = 50
	simulation.update_stage_spawning()
	assert simulation.zone == 1
	assert simulation.level == 1
	assert simulation.remaining_time_ms == 50_000
	assert simulation.zone_transition_ticks == 60
	for _ in 0 .. 61 {
		simulation.update_stage_spawning()
	}
	assert simulation.zone == 2
	assert simulation.level == 1.5
}

fn test_full_enemy_pool_still_consumes_a_scheduled_boss() {
	mut simulation := new_simulation(SimulationConfig{
		stage_progression: true
		enemy_capacity: 0
		barrage: Barrage{ emitters: [] }
	})
	simulation.stage.in_boss_mode = true
	simulation.next_boss_spec = 0
	simulation.next_boss_distance = 0
	simulation.update_stage_spawning()
	assert simulation.next_boss_spec == 1
	assert simulation.next_boss_distance >= 60
	assert simulation.next_boss_distance <= 89
	assert simulation.zone_transition_ticks == 60
}

fn test_procedural_course_is_seeded_and_uses_expected_length_chunks() {
	first := generate_course(123)
	second := generate_course(123)
	assert first == second
	assert first.slices.len >= 5000
	assert first.slices.len <= 5092
	assert first.slices.any(!it.full)
	assert first.rings.len > 1
	assert first.rings[0] == CourseRing{ index: 5, is_final: true }
	assert first.rings[..8].map(it.index) == [5, 120, 368, 481, 677, 934, 1193, 1412]
	for index in 1 .. first.rings.len {
		spacing := first.rings[index].index - first.rings[index - 1].index
		assert spacing >= 100
		assert spacing <= 299
		assert !first.rings[index].is_final
	}
	assert first.rings.last().index < first.slices.len - 100
}

fn test_course_side_and_live_boundary_correction() {
	slice := CourseSlice{
		left: 1
		right: 2
		rad: 21
	}
	assert course_side(1.5, slice) == 0
	assert course_side(0.5, slice) == -1
	assert course_side(2.5, slice) == 1
	mut simulation := new_simulation(SimulationConfig{
		procedural_course: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.course = CourseProfile{ slices: [slice] }
	simulation.ship.angle = 2.5
	simulation.ship.speed = 1
	simulation.ship.target_speed = 1
	simulation.update_ship(InputState{})
	assert simulation.ship.angle < 2
	assert simulation.ship.angle > 1.8
	assert course_side(simulation.ship.angle, slice) == 0
	assert simulation.ship.speed < 1
	assert simulation.ship.hits == 0
	vertices := simulation.render_course_vertices(2, 8)
	// The far ring reaches zero coverage, including its two side outlines.
	assert vertices.len == 256
	mut visible := 0
	mut hidden := 0
	for index := 3; index < vertices.len; index += 4 {
		if vertices[index] > 0 {
			visible++
		} else {
			hidden++
		}
	}
	assert visible > 0
	assert hidden > 0
}

fn test_walkable_border_contact_eases_inside_smaller_collision_margin() {
	slice := CourseSlice{
		left: 1
		right: 2
		rad: 21
	}
	mut simulation := new_simulation(SimulationConfig{
		procedural_course: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.course = CourseProfile{ slices: [slice] }
	simulation.ship.angle = 1.001
	before := simulation.ship.angle
	simulation.update_ship(InputState{})
	assert simulation.ship.angle > before
	assert simulation.ship.angle < 1.2
	assert course_side(simulation.ship.angle, slice) == 0
}

fn test_ship_collision_footprint_is_blocked_inside_a_shrinking_course_edge() {
	slice := CourseSlice{
		left: 1
		right: 2
		rad: 21
	}
	constrained_left, left_angle, left_side := ship_course_constraint(1.01, slice, 0.1)
	assert constrained_left
	assert f32(math.abs(left_angle - 1.1)) < 0.000001
	assert left_side == -1
	constrained_right, right_angle, right_side := ship_course_constraint(1.99, slice, 0.1)
	assert constrained_right
	assert f32(math.abs(right_angle - 1.9)) < 0.000001
	assert right_side == 1

	narrow := CourseSlice{
		left: 1.4
		right: 1.55
		rad: 21
	}
	constrained_narrow, centered_angle, _ := ship_course_constraint(1.2, narrow, 0.1)
	assert constrained_narrow
	assert f32(math.abs(centered_angle - 1.475)) < 0.000001
}

fn test_ship_course_footprint_constraint_handles_wrapped_open_track() {
	wrapped := CourseSlice{
		left: 6.0
		right: 0.5
		rad: 21
	}
	constrained, angle, side := ship_course_constraint(0.49, wrapped, 0.1)
	assert constrained
	assert f32(math.abs(angle - 0.4)) < 0.000001
	assert side == 1
	inside, unchanged, _ := ship_course_constraint(0.2, wrapped, 0.1)
	assert !inside
	assert unchanged == f32(0.2)
}

fn test_ship_angular_motion_preserves_lateral_speed_across_tunnel_radii() {
	mut simulation := new_simulation(SimulationConfig{
		procedural_course: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 42 }]
	}
	simulation.ship.bank = 1
	simulation.update_ship(InputState{})
	assert f32(math.abs(simulation.ship.angle - 0.036)) < 0.000001
}

fn test_boss_and_zone_exit_states_disable_over_acceleration() {
	mut unrestricted := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	unrestricted.ship.relative_depth = relative_depth_max
	unrestricted.ship.target_speed = 1
	unrestricted.update_ship(InputState{ up: true })
	assert unrestricted.ship.target_speed > 1

	mut boss := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	boss.ship.relative_depth = relative_depth_max
	boss.ship.target_speed = 1
	boss.stage.in_boss_mode = true
	boss.update_ship(InputState{ up: true })
	assert boss.ship.target_speed < 1

	mut exiting := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	exiting.ship.relative_depth = relative_depth_max
	exiting.ship.target_speed = 1
	exiting.stage.zone_complete_pending = true
	exiting.update_ship(InputState{ up: true })
	assert exiting.ship.target_speed < 1
}

fn test_full_level_transition_fades_then_changes_music_after_ninety_ticks() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.zone = 2
	simulation.stage.in_boss_mode = true
	simulation.stage.bosses_remaining = 1
	simulation.record_enemy_rank_up(true)
	assert simulation.music_fades == 1
	assert simulation.music_change_ticks == 90
	for _ in 0 .. 89 {
		simulation.update_music_transition()
	}
	assert simulation.music_changes == 0
	assert simulation.music_change_ticks == 1
	simulation.update_music_transition()
	assert simulation.music_changes == 1
	assert simulation.music_change_ticks == -1
}

fn test_enemy_speed_uses_restart_and_zone_exit_adjustments() {
	mut restarting := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	restarting.ship.lifecycle_counter = -229
	mut restart_enemy := Enemy{ alive: true, position: Vec2{ y: 20 } }
	restarting.prepare_generated_enemy_motion(mut restart_enemy, false)
	assert f32(math.abs(restart_enemy.speed - 0.2)) < 0.000001

	mut exiting := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	exiting.zone_transition_ticks = 60
	mut exit_enemy := Enemy{
		alive: true
		position: Vec2{ y: 20 }
		speed: 1
		flip_ticks: 10
		flip_velocity: Vec2{ x: 1, y: 2 }
	}
	exiting.prepare_generated_enemy_motion(mut exit_enemy, false)
	assert f32(math.abs(exit_enemy.speed - 0.78)) < 0.000001
	assert exit_enemy.flip_ticks == 0
	assert exit_enemy.flip_velocity == Vec2{}
}

fn test_course_render_vertices_accumulate_slice_bends_relative_to_ship() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.course = CourseProfile{
		slices: [CourseSlice{ full: true, rad: 21, turn_x: 0.005 },
			CourseSlice{ full: true, rad: 21, turn_x: 0.005 }]
	}
	vertices := simulation.render_course_vertices(2, 8)
	first_ring_x := vertices[0]
	second_ring_x := vertices[64]
	// Both rings are behind the ship origin. The older ring has accumulated
	// more curvature; approaching the ship therefore reduces its offset.
	assert first_ring_x > second_ring_x
	assert second_ring_x > 0
}

fn test_tunnel_palette_matches_expected_pairs_and_zone_cadence() {
	mut simulation := new_simulation(SimulationConfig{
		starting_level: 1
		barrage: Barrage{ emitters: [] }
	})
	initial := simulation.tunnel_line_color()
	assert initial == RgbColor{ r: 0.6, g: 0.4, b: 1 }
	assert simulation.tunnel_poly_color() == RgbColor{ r: 0.8, g: 0.5, b: 0.9 }
	simulation.palette_transition_ticks = 0
	zone_one := simulation.tunnel_line_color()
	assert zone_one == RgbColor{ r: 0.6, g: 0.7, b: 1 }
	assert simulation.tunnel_poly_color() == RgbColor{ r: 0.7, g: 0.9, b: 1 }
	simulation.zone = 3
	simulation.level = 2
	zone_three := simulation.tunnel_line_color()
	assert zone_three == RgbColor{ r: 0.4, g: 0.8, b: 0.6 }

	mut later_start := new_simulation(SimulationConfig{
		starting_level: 4
		barrage: Barrage{ emitters: [] }
	})
	later_start.palette_transition_ticks = 0
	assert later_start.tunnel_line_color() == RgbColor{ r: 0.6, g: 0.6, b: 0.6 }
	assert later_start.tunnel_poly_color() == RgbColor{ r: 0.8, g: 0.8, b: 0.8 }
	later_start.zone = 2
	later_start.level = 4.5
	assert later_start.tunnel_line_color() == RgbColor{ r: 0.6, g: 0.6, b: 0.6 }
	later_start.zone = 3
	later_start.level = 5
	assert later_start.tunnel_line_color() == RgbColor{ r: 0.4, g: 0.7, b: 0.7 }
}

fn test_tunnel_dark_line_ratio_alternates_and_transitions_over_sixty_ticks() {
	mut simulation := new_simulation(SimulationConfig{ barrage: Barrage{ emitters: [] } })
	simulation.zone = 1
	simulation.palette_transition_ticks = 60
	assert simulation.tunnel_dark_line_ratio() == 1
	simulation.palette_transition_ticks = 30
	assert simulation.tunnel_dark_line_ratio() == 0.5
	simulation.palette_transition_ticks = 0
	assert simulation.tunnel_dark_line_ratio() == 0
	simulation.zone = 2
	assert simulation.tunnel_dark_line_ratio() == 1
	simulation.palette_transition_ticks = 60
	assert simulation.tunnel_dark_line_ratio() == 0
}

fn test_dark_tunnel_recurrence_dims_near_lines_and_brightens_near_lights() {
	bright_lines, bright_lights := tunnel_slice_brightness(72, 0)
	dark_lines, dark_lights := tunnel_slice_brightness(72, 1)
	assert bright_lines[71] == dark_lines[71]
	assert dark_lines[0] < bright_lines[0]
	assert dark_lights[50] < bright_lights[50]
	assert dark_lights[0] > bright_lights[0]
	assert bright_lines[0] > bright_lines[35]
	assert bright_lines[35] > bright_lines[70]
	assert bright_lines[71] == 0
	assert bright_lights[71] == 0
}

fn test_score_extension_is_capped_at_initial_run_time() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		barrage: Barrage{ emitters: [] }
	})
	simulation.remaining_time_ms = 118_000
	simulation.score = 100001
	simulation.update()
	assert simulation.time_extensions == 1
	assert simulation.remaining_time_ms == 119_983
	assert simulation.next_extend_score == 200000
	assert simulation.time_change_seconds == 15
	assert simulation.time_change_ticks == 239
}

fn test_final_seconds_increment_warning_beeps() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 1000
		barrage: Barrage{ emitters: [] }
	})
	simulation.update()
	assert simulation.warning_beeps == 1
}

fn test_boss_destruction_advances_zone_and_adds_time() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.remaining_time_ms = 50_000
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		health: 30
		kind: 2
		score: 2000
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 3.285 }
		range: 35
		charged: true
		damage: 100
	}
	simulation.update()
	assert simulation.destroyed_boss == 1
	assert simulation.zone == 2
	assert simulation.zone_advances == 1
	assert simulation.remaining_time_ms == 79_983
}

fn test_zone_bonuses_alternate_thirty_and_forty_five_seconds() {
	mut simulation := new_simulation(SimulationConfig{
		run_time_ms: 120_000
		barrage: Barrage{ emitters: [] }
	})
	simulation.remaining_time_ms = 20_000
	simulation.advance_zone()
	assert simulation.zone == 2
	assert simulation.level == 1.5
	assert simulation.remaining_time_ms == 50_000
	assert simulation.time_change_seconds == 30
	assert simulation.time_change_ticks == 240
	simulation.remaining_time_ms = 20_000
	simulation.advance_zone()
	assert simulation.zone == 3
	assert simulation.level == 2
	assert simulation.remaining_time_ms == 65_000
	assert simulation.time_change_seconds == 45
	assert simulation.time_change_ticks == 240
}

fn test_three_player_shots_destroy_enemy_and_score() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		health: 3
	}
	for _ in 0 .. 3 {
		simulation.shots[0] = Shot{
			alive: true
			position: Vec2{ x: 0, y: simulation.enemies[0].position.y - 0.715 }
			range: 35
		}
		simulation.update()
	}
	assert !simulation.enemies[0].alive
	assert simulation.destroyed_enemies == 1
	assert simulation.score == 300
	small_collision := ship_shape_collision(0, 0)
	fragment_count := if small_collision.x < 0.5 { 0 } else { int(small_collision.x * 40) }
	// Two eight-spark nonlethal impacts plus the source-defined core and fragments.
	assert living_destruction_particles(&simulation) == 46 + fragment_count
}

fn test_nonlethal_enemy_hit_flashes_and_emits_eight_opposed_sparks() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		health: 2
		kind: 1
		score: 500
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 3.285 }
		range: 35
	}
	simulation.update_shots()
	assert simulation.enemies[0].health == 1
	assert simulation.enemies[0].damaged
	assert simulation.score == 500
	assert simulation.living_particles() == 8
	simulation.update_enemies()
	assert !simulation.enemies[0].damaged
}

fn test_normal_shot_scores_every_overlapping_enemy_in_pool_order() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		enemy_capacity: 2
		shot_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	for index in 0 .. 2 {
		simulation.enemies[index] = Enemy{
			alive: true
			position: Vec2{ x: 0, y: 4 }
			health: 1
			score: 100
		}
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		range: 35
	}
	simulation.update_shots()
	assert !simulation.shots[0].alive
	assert simulation.destroyed_enemies == 2
	assert simulation.score == 200
}

fn test_charged_shot_multiplier_advances_on_a_nonlethal_hit() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		enemy_capacity: 1
		shot_capacity: 1
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		health: 300
		score: 500
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 4 }
		range: 35
		charged: true
		damage: 100
	}
	simulation.update_shots()
	assert simulation.enemies[0].health == 200
	assert simulation.score == 500
	assert simulation.shots[0].multiplier == 2
}

fn test_destruction_particles_expire_deterministically() {
	mut simulation := new_simulation(SimulationConfig{
		barrage: Barrage{ emitters: [] }
	})
	simulation.spawn_particles(Vec2{ x: 1, y: 2 }, 3, 2, .spark)
	assert simulation.living_particles() == 3
	simulation.update()
	assert living_destruction_particles(&simulation) == 3
	simulation.update()
	assert living_destruction_particles(&simulation) == 3
	simulation.update()
	assert living_destruction_particles(&simulation) == 0
}

fn test_boss_destruction_combines_impact_core_and_scaled_fragments() {
	mut simulation := new_simulation(SimulationConfig{
		collisions: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.enemies[0] = Enemy{
		alive: true
		kind: 2
		health: 1
		position: Vec2{ x: 0, y: 4 }
	}
	simulation.shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0, y: 3.285 }
		range: 35
	}
	simulation.update()
	mut sparks := 0
	mut fragments := 0
	for particle in simulation.particles {
		if !particle.alive {
			continue
		}
		if particle.kind == .spark { sparks++ }
		if particle.kind == .fragment { fragments++ }
	}
	assert sparks == 30
	expected_fragments := int(ship_shape_collision(2, 0).x * 40)
	assert fragments == expected_fragments
	assert living_destruction_particles(&simulation) == 30 + expected_fragments
	collision := ship_shape_collision(2, 0)
	for particle in simulation.particles {
		if particle.alive && particle.kind == .fragment {
			assert particle.fragment_width >= collision.x
			assert particle.fragment_width < collision.x * 2
			assert particle.fragment_height >= collision.y
			assert particle.fragment_height < collision.y * 2
		}
	}
}

fn test_fragment_dual_spin_and_scale_follow_source_decay() {
	mut simulation := new_simulation(SimulationConfig{ particle_capacity: 1 })
	simulation.particles[0] = Particle{
		alive: true
		life: 10
		initial_life: 10
		kind: .fragment
		height: 1
		spin_velocity: 0.2
		secondary_spin_velocity: -0.3
		fragment_width: 2
		fragment_height: 4
	}
	simulation.update_particles()
	assert simulation.particles[0].spin == 0.2
	assert simulation.particles[0].secondary_spin == -0.3
	assert f32(math.abs(simulation.particles[0].spin_velocity - 0.196)) < 0.000001
	assert f32(math.abs(simulation.particles[0].secondary_spin_velocity + 0.294)) < 0.000001
	assert f32(math.abs(simulation.particles[0].scale - 0.98)) < 0.000001
}

fn test_particle_height_uses_expected_gravity_and_tunnel_bounce() {
	mut simulation := new_simulation(SimulationConfig{ particle_capacity: 1 })
	simulation.particles[0] = Particle{
		alive: true
		position: Vec2{ x: 1, y: 3 }
		life: 10
		initial_life: 10
		height: 0.01
		height_velocity: -0.1
		in_course: true
		kind: .spark
	}
	simulation.update_particles()
	assert simulation.particles[0].height > 0
	assert simulation.particles[0].height_velocity > 0
	assert simulation.particles[0].luminosity == 0.98
}

fn test_generated_barrage_propagates_hostile_bullet_shape() {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.fire_generated_barrage(Vec2{ x: 1, y: 20 }, 3.14, GeneratedBarrageSpec{
		base_pattern: 'basic/straight'
		rank: 0.2
		speed_rank: 0.75
		bullet_shape: 4
	})
	assert simulation.living_bullets() > 0
	for bullet in simulation.bullets {
		if bullet.alive {
			assert bullet.visual_shape == 4
			assert bullet.speed_rank == 0.75
			assert f32(math.abs(bullet.speed - f32(10.0 / 62.0))) < 0.000001
		}
	}
}

fn test_generated_barrage_propagates_expected_range_and_mirroring_flags() {
	mut simulation := new_simulation(SimulationConfig{})
	simulation.fire_generated_barrage(Vec2{ x: 1, y: 140 }, 3.14, GeneratedBarrageSpec{
		base_pattern: 'basic/straight'
		rank: 0.2
		speed_rank: 1
		long_range: true
		no_x_reverse: true
		visual_scale: 1.2
	})
	assert simulation.living_bullets() > 0
	for bullet in simulation.bullets {
		if bullet.alive {
			assert bullet.long_range
			assert bullet.x_reverse == 1
			assert bullet.visual_scale == 1.2
		}
	}
}

fn test_bullet_lifecycle_matches_expected_sight_and_screen_rules() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 3
		barrage: Barrage{ emitters: [] }
	})
	simulation.bullets[0] = Bullet{
		alive: true
		position: Vec2{ x: simulation.ship.eye_angle, y: simulation.ship.sight_depth + 1 }
	}
	simulation.bullets[1] = Bullet{
		alive: true
		position: Vec2{ x: simulation.ship.eye_angle, y: 140 }
		long_range: true
	}
	simulation.bullets[2] = Bullet{
		alive: true
		position: Vec2{ x: f32(math.pi), y: 20 }
		long_range: true
	}
	simulation.update_bullets()
	assert simulation.bullets[0].disappear_ticks == 2
	assert simulation.bullets[1].disappear_ticks == 0
	assert simulation.bullets[2].disappear_ticks == 2
}

fn test_enemy_fire_originates_from_enemy_on_schedule() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_interval: 1000
		enemy_fire_interval: 75
		barrage: Barrage{ emitters: [] }
	})
	for _ in 0 .. 75 {
		simulation.update()
	}
	assert simulation.enemy_shots_fired == 1
	assert simulation.living_bullets() == 1
	assert simulation.bullets[0].position.y < simulation.enemies[0].position.y
}

fn test_aim_direction_uses_shortest_route_across_tunnel_seam() {
	from := Vec2{ x: 6.27, y: 20 }
	to := Vec2{ x: 0.01, y: 0 }
	direction := aim_direction_reversed(from, to, 1)
	assert direction > 3.0
	assert direction < 3.2
	reversed := aim_direction_reversed(from, to, -1)
	assert reversed < -3.0
	assert reversed > -3.2
}
