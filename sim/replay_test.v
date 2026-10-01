module sim

fn test_replay_input_round_trip() {
	input := InputState{ left: true, down: true, fire: true }
	assert decode_input(encode_input(input)) == input
}

fn test_replayed_inputs_reproduce_simulation_checksum() {
	config := SimulationConfig{ random_seed: 92821 }
	mut recorded := new_simulation(config)
	mut inputs := []u8{}
	for tick in 0 .. 420 {
		input := InputState{
			left: tick % 90 < 20
			right: tick % 90 >= 50
			up: tick % 75 < 8
			fire: tick % 7 < 3
			brake: tick >= 180 && tick < 215
		}
		inputs << encode_input(input)
		recorded.update_with_input(input)
	}
	mut replayed := new_simulation(config)
	for value in inputs {
		replayed.update_with_input(decode_input(value))
	}
	assert replayed.checksum() == recorded.checksum()
}

fn test_replay_retains_overtaken_enemy_until_expected_rear_depth() {
	mut simulation := new_simulation(SimulationConfig{
		replay_mode: true
		stage_progression: true
		barrage: Barrage{ emitters: [] }
	})
	simulation.next_small_distance = 9999
	simulation.next_middle_distance = 9999
	simulation.ship.speed = 1
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: -5.1 }
		health: 1
		rank_counted: true
	}
	simulation.update_enemies()
	assert !simulation.enemies[0].alive
	passed_index := simulation.passed_enemies.len - 1
	assert simulation.passed_enemies[passed_index].alive
	assert simulation.passed_enemies[passed_index].age == 1
	assert simulation.passed_enemies[passed_index].position.y < -5.1
	assert simulation.enemy_shots_fired == 0
	simulation.passed_enemies[passed_index].position.y = -105.1
	simulation.update_passed_enemies()
	assert !simulation.passed_enemies[passed_index].alive
}

fn test_passed_enemy_pool_allocates_backwards_from_its_own_cursor() {
	mut simulation := new_simulation(SimulationConfig{
		replay_mode: true
		enemy_capacity: 3
	})
	assert simulation.spawn_passed_enemy(Enemy{ alive: true })
	assert simulation.passed_enemies[2].alive
	assert simulation.spawn_passed_enemy(Enemy{ alive: true })
	assert simulation.passed_enemies[1].alive
}

fn test_passed_enemy_never_moves_forward_relative_to_ship() {
	mut simulation := new_simulation(SimulationConfig{
		replay_mode: true
		stage_progression: true
	})
	simulation.ship.speed = 1
	simulation.passed_enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 1, y: -10 }
		speed: 2
	}
	simulation.update_passed_enemies()
	assert simulation.passed_enemies[0].position.y == -10
}
