module sim

import math

fn test_pattern_expression_supports_rank_parameters_and_seeded_randomness() {
	// 1 + rank * 5.2 + $1 - random
	expression := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 1 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 5.2 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .add },
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .add },
			ValueToken{ op: .random },
			ValueToken{ op: .subtract },
		]
	}
	mut first := new_mt19937(7)
	mut second := new_mt19937(7)
	value := expression.evaluate(0.5, [f32(2)], mut first) or { panic(err) }
	random := second.next_f32(1)
	assert f32(math.abs(value - (5.6 - random))) < 0.00001
}

fn test_native_straight_pattern_fires_relative_to_its_owner() {
	program := straight_pattern()
	mut runner := new_pattern_runner(program, PatternContext{
		base_direction: 1.25
		base_speed: 0.4
	})
	mut rng := new_mt19937(1)
	shots := runner.tick(mut rng) or { panic(err) }
	assert shots.len == 1
	assert shots[0].direction == 1.25
	assert shots[0].speed == 0.4
	assert !runner.alive
}

fn test_pattern_speed_units_match_the_bulletml_conversion() {
	unit := f32(10.0 / 62.0)
	mut omitted := new_pattern_runner(straight_pattern(), PatternContext{
		base_direction: 1.25
		default_speed: unit
		speed_scale: unit
	})
	mut rng := new_mt19937(1)
	omitted_shots := omitted.tick(mut rng) or { panic(err) }
	assert omitted_shots.len == 1
	assert omitted_shots[0].speed == unit

	explicit_program := PatternProgram{
		name: 'explicit_speed'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				speed: literal_expression(2)
			},
			PatternInstruction{ op: .end },
		]
	}
	mut explicit := new_pattern_runner(explicit_program, PatternContext{
		default_speed: unit
		speed_scale: unit
	})
	explicit_shots := explicit.tick(mut rng) or { panic(err) }
	assert explicit_shots.len == 1
	assert f32(math.abs(explicit_shots[0].speed - 2 * unit)) < 0.000001
}

fn test_native_nway_pattern_executes_ranked_repeats_and_sequences() {
	program := nway_pattern()
	mut runner := new_pattern_runner(program, PatternContext{
		rank: 0.5
		base_speed: 0.1
	})
	mut rng := new_mt19937(2)
	shots := runner.tick(mut rng) or { panic(err) }
	assert shots.len == 7
	assert shots[0].direction == 0
	step := f32(2.5 * math.pi / 180.0)
	assert f32(math.abs(shots[3].direction - step * 3)) < 0.000001
	assert f32(math.abs(shots[4].direction + step)) < 0.000001
	assert f32(math.abs(shots[6].direction + step * 3)) < 0.000001
	assert runner.wait_ticks == 50
	for _ in 0 .. 50 {
		assert runner.tick(mut rng)!.len == 0
	}
	assert runner.alive
	assert runner.tick(mut rng)!.len == 0
	assert !runner.alive
}

fn test_action_calls_bind_parameters_and_restore_the_caller() {
	mut runner := new_pattern_runner(alternating_nway_pattern(), PatternContext{
		rank: 0.5
		base_speed: 0.1
	})
	mut rng := new_mt19937(3)
	first := runner.tick(mut rng) or { panic(err) }
	assert first.len == 3
	assert first[1].direction > first[0].direction
	assert first[2].direction > first[1].direction
	assert runner.wait_ticks == 45
	for _ in 0 .. 45 {
		assert runner.tick(mut rng)!.len == 0
	}
	second := runner.tick(mut rng) or { panic(err) }
	assert second.len == 3
	assert second[1].direction < second[0].direction
	assert second[2].direction < second[1].direction
	assert runner.wait_ticks == 45
}

fn test_top_pattern_rewinds_with_expected_pre_and_post_waits() {
	mut looping := new_looping_pattern_runner(straight_pattern(), PatternContext{
		base_direction: 0.75
		base_speed: 0.2
	}, 2, 3)
	mut rng := new_mt19937(4)
	assert looping.tick(mut rng)!.len == 0
	assert looping.tick(mut rng)!.len == 0
	first := looping.tick(mut rng) or { panic(err) }
	assert first.len == 1
	assert first[0].direction == 0.75
	assert looping.tick(mut rng)!.len == 0
	assert looping.tick(mut rng)!.len == 0
	assert looping.tick(mut rng)!.len == 0
	second := looping.tick(mut rng) or { panic(err) }
	assert second.len == 1
}

fn test_native_catalog_names_are_unique() {
	catalog := native_pattern_catalog()
	assert catalog.len == 28
	mut names := map[string]bool{}
	for program in catalog {
		assert program.name !in names
		names[program.name] = true
	}
}

fn test_multi_root_patterns_execute_top_actions_concurrently() {
	mut rng := new_mt19937(12)
	mut thirty_five := new_parallel_pattern_runner(thirty_five_way_pattern(), PatternContext{
		rank: 0
		base_speed: 0.5
	}, 0, 0) or { panic(err) }
	first := thirty_five.tick(mut rng) or { panic(err) }
	assert first.len == 3
	assert thirty_five.runners[0].runner.wait_ticks == 72
	assert thirty_five.runners[1].runner.wait_ticks == 26

	mut diamond := new_parallel_pattern_runner(diamond_nway_pattern(), PatternContext{
		rank: 0
		base_speed: 0.5
	}, 0, 0) or { panic(err) }
	initial := diamond.tick(mut rng) or { panic(err) }
	assert initial.len == 2
	assert diamond.runners[0].runner.wait_ticks == 4
	assert diamond.runners[1].runner.wait_ticks == 4
	for _ in 0 .. 4 {
		assert diamond.tick(mut rng)!.len == 0
	}
	spread := diamond.tick(mut rng) or { panic(err) }
	assert spread.len == 2
	assert spread[0].direction < 0
	assert spread[1].direction > 0
}

fn test_new_single_root_patterns_reach_their_first_wait() {
	mut rng := new_mt19937(11)
	mut sideshot := new_pattern_runner(alternating_sideshot_pattern(), PatternContext{
		rank: 0
		base_speed: 0.5
	})
	assert sideshot.tick(mut rng)!.len == 2
	assert sideshot.wait_ticks == 2

	mut grow_three := new_pattern_runner(grow_three_way_pattern(), PatternContext{
		rank: 0
		base_speed: 0.5
	})
	assert grow_three.tick(mut rng)!.len == 3
	assert grow_three.wait_ticks == 4

	mut squirt := new_pattern_runner(squirt_pattern(), PatternContext{
		rank: 0
		base_speed: 0.5
	})
	assert squirt.tick(mut rng)!.len == 1
	assert squirt.wait_ticks == 20
}

fn test_speed_and_direction_changes_finish_on_the_requested_tick() {
	program := PatternProgram{
		name: 'transition_test'
		instructions: [
			PatternInstruction{
				op: .change_speed
				value: literal_expression(1.5)
				speed_mode: .relative
				term: literal_expression(60)
			},
			PatternInstruction{
				op: .change_direction
				value: literal_expression(90)
				direction_mode: .relative
				term: literal_expression(60)
			},
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{ op: .end },
		]
	}
	mut runner := new_pattern_runner(program, PatternContext{
		base_direction: 0.25
		base_speed: 0.5
	})
	mut rng := new_mt19937(6)
	assert runner.tick(mut rng)!.len == 0
	assert runner.speed == 0.5
	assert runner.direction == 0.25
	for _ in 0 .. 60 {
		assert runner.tick(mut rng)!.len == 0
	}
	assert runner.speed == 2
	assert f32(math.abs(runner.direction - (0.25 + math.pi / 2))) < 0.000001
}

fn test_fast_morph_fires_at_its_transitioned_speed() {
	mut runner := new_pattern_runner(fast_pattern(), PatternContext{
		rank: 1
		base_speed: 0.5
	})
	mut rng := new_mt19937(7)
	assert runner.tick(mut rng)!.len == 0
	for _ in 0 .. 60 {
		assert runner.tick(mut rng)!.len == 0
	}
	shots := runner.tick(mut rng) or { panic(err) }
	assert shots.len == 1
	assert shots[0].speed == 2
}

fn test_spawned_bullet_can_continue_at_a_parameterized_child_action() {
	child_angle := ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: 1 }]
	}
	child_parameter := ValueExpression{
		tokens: [
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 1 },
			ValueToken{ op: .add },
		]
	}
	program := PatternProgram{
		name: 'child_action_test'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				bullet_entry: 2
				bullet_parameters: [child_parameter]
			},
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .fire
				value: child_angle
				direction_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
	mut rng := new_mt19937(8)
	mut parent := new_pattern_runner(program, PatternContext{
		rank: 0.5
		base_direction: 1
		base_speed: 0.2
	})
	spawned := parent.tick(mut rng) or { panic(err) }
	assert spawned.len == 1
	assert spawned[0].action_entry == 2
	assert spawned[0].parameters == [f32(1.5)]
	mut child := new_pattern_runner_at(program, PatternContext{
		rank: 0.5
		parameters: spawned[0].parameters
		base_direction: spawned[0].direction
		base_speed: spawned[0].speed
	}, spawned[0].action_entry) or { panic(err) }
	continued := child.tick(mut rng) or { panic(err) }
	assert continued.len == 1
	assert f32(math.abs(continued[0].direction - (1 + 1.5 * math.pi / 180.0))) < 0.000001
}

fn test_twin_children_turn_out_and_restore_direction_before_firing() {
	program := twin_pattern()
	mut rng := new_mt19937(9)
	mut parent := new_pattern_runner(program, PatternContext{
		rank: 0.5
		base_direction: 1
		base_speed: 0.5
	})
	assert parent.tick(mut rng)!.len == 0
	assert parent.tick(mut rng)!.len == 0
	spawned := parent.tick(mut rng) or { panic(err) }
	assert spawned.len == 2
	assert spawned[0].parameters == [f32(90)]
	assert spawned[1].parameters == [f32(-90)]
	mut child := new_pattern_runner_at(program, PatternContext{
		rank: 0.5
		parameters: spawned[0].parameters
		base_direction: spawned[0].direction
		base_speed: spawned[0].speed
	}, spawned[0].action_entry) or { panic(err) }
	assert child.tick(mut rng)!.len == 0
	assert child.tick(mut rng)!.len == 0
	assert f32(math.abs(child.direction - (1 + math.pi / 2))) < 0.000001
	assert child.tick(mut rng)!.len == 0
	assert child.tick(mut rng)!.len == 0
	continued := child.tick(mut rng) or { panic(err) }
	assert continued.len == 1
	assert f32(math.abs(continued[0].direction - 1)) < 0.000001
	assert continued[0].speed == 0.5
}

fn test_random_fire_is_seeded_and_uses_expected_wait_formula() {
	context := PatternContext{ rank: 0.5, base_speed: 0.1 }
	mut first := new_pattern_runner(random_fire_pattern(), context)
	mut second := new_pattern_runner(random_fire_pattern(), context)
	mut first_rng := new_mt19937(99)
	mut second_rng := new_mt19937(99)
	first_shots := first.tick(mut first_rng) or { panic(err) }
	second_shots := second.tick(mut second_rng) or { panic(err) }
	assert first_shots == second_shots
	assert first.wait_ticks == 11
}

fn test_morph_programs_preserve_relative_and_sequence_speeds() {
	mut divide := new_pattern_runner(divide_pattern(), PatternContext{
		rank: 0.5
		base_direction: 1
		base_speed: 0.8
	})
	mut rng := new_mt19937(5)
	divided := divide.tick(mut rng) or { panic(err) }
	assert divided.len == 2
	assert divided[0].speed == 0.7
	assert divided[1].speed == 0.7
	assert divided[0].direction > 1
	assert divided[1].direction < 1

	mut bar := new_pattern_runner(bar_pattern(), PatternContext{
		rank: 0.6
		base_speed: 0.5
	})
	barred := bar.tick(mut rng) or { panic(err) }
	assert barred.len == 2
	assert barred[0].speed == 0.5
	assert barred[1].speed > barred[0].speed
}
